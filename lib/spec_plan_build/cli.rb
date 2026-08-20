# frozen_string_literal: true

module SpecPlanBuild
  # The command line. Everything here is a thin shell over the classes above:
  # a command parses flags, calls one object, and prints the result.
  #
  # Two conventions hold throughout:
  #
  #   * The deliverable goes to STDOUT, progress and boxes go to STDERR, so
  #     every command composes in a pipe.
  #   * Anything that writes to disk or to GitHub is DRY RUN by default and
  #     needs `--commit`. Folder names and pull request titles are joined on by
  #     branches, `pull-requests.md` and merged history; changing one silently
  #     is how a plan ends up filed under work it did not do.
  module CLI
    extend Dry::CLI::Registry

    # Shared flags and the plumbing every command needs.
    class Base < Dry::CLI::Command
      include UI

      def self.inherited(klass)
        super
        klass.option :dir, default: SpecPlanBuild::PLANS_DIR, aliases: ["-D"],
          desc:          "The .plans directory"
        klass.option :quiet, type: :boolean, default: false, aliases: ["-q"],
          desc:         "Suppress progress output on STDERR"
      end

      private

      # @param options [Hash]
      # @return [SpecPlanBuild::Tree]
      def tree_for(options)
        tree = Tree.new(dir: options.fetch(:dir, SpecPlanBuild::PLANS_DIR))
        unless tree.exist?
          error("No #{SpecPlanBuild::PLANS_DIR} directory at\n#{tree.dir}\n\n" \
                  "Run this from the project root, or pass -D.")
          exit 66
        end
        tree
      end

      # @param options [Hash]
      # @return [Boolean]
      def quiet?(options)
        quiet = options.fetch(:quiet, false)
        UI.quiet = quiet
        quiet
      end

      # @param options [Hash]
      # @return [Boolean]
      def commit?(options) = options.fetch(:commit, false)

      # The line every dry run ends with, so nobody mistakes a preview for the
      # thing having happened.
      #
      # @param count [Integer] how much work is pending
      # @param what [String]
      # @return [void]
      def dry_run_footer(count, what)
        return if count.zero?

        warn("#{count} #{what} pending — nothing was changed.\nRe-run with --commit to apply.")
      end
    end

    # `spec-plan-build create <words…>` — backs /spec-create.
    class Create < Base
      desc "Create the next numbered plan folder"

      argument :words, type: :array, required: true,
        desc:         "The topic, two to five words; becomes the folder slug"

      option :after, aliases: ["-a"],
        desc:            "Create a retroactive plan in the gap after this plan, e.g. 002"
      option :status, aliases: ["-s"],
        desc:             "Open in a state other than the default"
      option :prs, aliases: ["--pr"],
        desc:          "Document work that already shipped: pull request numbers or URLs, comma separated. Requires --after"
      option :spec, type: :boolean, default: true,
        desc:           "With --prs, write spec.md from what the pull requests did. --no-spec records them and stops, which is fast and offline"

      # noinspection RubyMismatchedArgumentType
      example [
        "tax rule dsl                        # 003.00-⚪️-tax-rule-dsl",
        "--after 002 schedule k1             # 002.01-🕰️-schedule-k1 (documented after the fact)",
        "--after 018 --prs 12,15 verify      # …and write spec.md from what those PRs did",
        "--after 018 --pr https://…/pull/12 verify",
        "--status ready billing sync         # opens at ⭐️ instead of ⚪️"
      ]

      # @param words [Array<String>]
      # @param options [Hash]
      # @return [void]
      def call(words:, **options)
        dir = options.fetch(:dir, SpecPlanBuild::PLANS_DIR)
        FileUtils.mkdir_p(dir)

        prs = fetch_prs(options)
        result = Creator.new(dir:).create(words:, after: options[:after],
          status: options[:status], prs:)

        result.either(
          ->(path) { created(path, prs, options) },
          lambda { |message|
            error("Could not create the plan:\n#{message}")
            exit 65
          }
        )
      end

      private

      # A retroactive plan documents work that landed *somewhere* in the
      # sequence, and only its author knows where. Guessing would put the
      # number — the one thing that never changes — in the wrong place.
      #
      # @param options [Hash]
      # @return [Array<Hash>, nil]
      def fetch_prs(options)
        return nil unless options[:prs]

        unless options[:after]
          error("--prs documents work that already shipped;\n" \
                "name the plan it landed after with --after, e.g. --after 018")
          exit 64
        end

        GitHub.new.pull_requests(GitHub.parse_refs(options[:prs]))
      rescue SpecPlanBuild::Error => e
        error("Could not read the pull requests:\n#{e.message}")
        exit 65
      end

      # @param path [String]
      # @param prs [Array<Hash>, nil]
      # @param options [Hash]
      # @return [void]
      def created(path, prs, options)
        path = synthesize(path, options) if prs && !prs.empty? && options.fetch(:spec, true)
        puts path
        return if quiet?(options)

        feature = Feature.parse(path)
        success("Created #{File.basename(path)}\n\n" \
                  "#{feature.status.emoji} #{feature.status.label} — #{feature.status.note}\n" \
                  "#{next_step(path, feature)}")
      end

      # Hand the folder to the writer that already knows how to write a
      # retroactive specification, then let `resync dirs` decide what the
      # folder has become — 🕰️ is only true while there is no `spec.md`.
      #
      # @param path [String]
      # @param options [Hash]
      # @return [String] the folder's path, which the resync may have renamed
      def synthesize(path, options)
        agent = Agents.new.find(SpecPlanBuild::RETROACTIVE_WRITER) or return path
        root = options[:root] || File.dirname(path, 2)

        ok, note = UI.spinning("Writing spec.md from #{File.basename(path)}") {
          Executor.new(root:).call(agent, Subject.new(Feature.parse(path)))
        }
        warn_about(note) unless ok

        settle(path)
      end

      # @param path [String]
      # @return [String] where the folder ended up
      def settle(path)
        tree = Tree.new(dir: File.dirname(path))
        change = SpecPlanBuild::Resync::Dirs.new(tree:).call(commit: true)
          .find { |c| c.source == path }
        change ? change.target : path
      end

      # @param note [String]
      # @return [void]
      def warn_about(note)
        error("The folder was created, but spec.md was not written:\n#{note}\n\n" \
              "The pull requests are recorded. Run `spec-plan-build run --commit` to retry.")
      end

      # @param path [String]
      # @param feature [SpecPlanBuild::Feature]
      # @return [String]
      def next_step(path, feature)
        return "Next: write #{File.join(File.basename(path), "spec.md")}" unless feature.status.key == :new && File.file?(File.join(path, "spec.md"))

        "Next: read #{File.join(File.basename(path), "spec.md")} — it was written from the pull requests, so check it against what actually shipped"
      end
    end

    # `spec-plan-build index` — the plans as one browsable page.
    class Index < Base
      desc "Write .plans/INDEX.md: every plan, its goal, its pull requests and its documents"

      option :output, aliases: ["-o"],
        desc:            "Write somewhere other than <plans>/INDEX.md; - for STDOUT"
      option :project, aliases: ["-p"],
        desc:             "Heading for the page, default: the repository's directory name"

      example [
        "                     # write .plans/INDEX.md",
        "-o -                 # print it instead",
        "-p 'Equilibris App'  # override the heading"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        index = SpecPlanBuild::Index.new(tree: tree_for(options), project: options[:project])

        if options[:output] == "-"
          $stdout.write(index.render)
          return
        end

        path = index.write(options[:output])
        puts path
        return if quiet?(options)

        success("Wrote #{path}\n\nRegenerate it after any `resync dirs`, which renames folders\nand would otherwise leave every link here pointing at nothing.")
      end
    end

    # `spec-plan-build status` — backs /spec-status.
    class Status < Base
      desc "Print every plan, its state, and its pull requests"

      example ["", "-D .plans", "| less -R"]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        reporter = Reporter.new(tree: tree_for(options))
        $stdout.write(reporter.render)

        exit 1 unless reporter.inconsistent.empty?
      end
    end

    # `spec-plan-build resync …`
    module Resync
      # `resync dirs` — reconcile folder names with folder contents.
      class Dirs < Base
        desc "Rename plan folders so the name matches the contents and the NNN.MM form"

        option :commit, type: :boolean, default: false,
          desc:          "Actually rename the folders (default: dry run)"

        example [
          "                # show what would be renamed",
          "--commit        # do it"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          changes = SpecPlanBuild::Resync::Dirs.new(tree: tree_for(options))
            .call(commit: commit?(options))

          if changes.empty?
            success("Every folder is already named NNN.MM-<emoji>-<slug> and the emoji matches.") unless quiet?(options)
            return
          end

          changes.each do |change|
            puts "#{change.dirname}\t#{File.basename(change.target)}\t#{change.reason}"
            next if quiet?(options)

            say("#{paint(change.dirname, :bright_black)} → #{File.basename(change.target)}")
            say("  #{paint(change.reason, :yellow)}", bullet: " ")
          end

          return if quiet?(options)

          if commit?(options)
            success("Renamed #{changes.size} folder#{"s" unless changes.size == 1}.")
          else
            dry_run_footer(changes.size, "rename#{"s" unless changes.size == 1}")
          end
        end
      end

      # `resync prs` — put an [NNN.MM] prefix on every pull request title.
      class Prs < Base
        desc "Add missing [NNN.MM] prefixes to pull request titles"

        option :commit, type: :boolean, default: false,
          desc:          "Actually retitle the pull requests (default: dry run)"
        option :state, default: "all", values: %w[open closed merged all],
          desc:            "Which pull requests to consider"
        option :adopt, type: :boolean, default: true,
          desc:           "Mint a retroactive plan folder for every pull request that resolves to none. --no-adopt flags them for a human instead"

        example [
          "                # show what would be retitled, and what would be adopted",
          "--state open    # only open pull requests",
          "--no-adopt      # never create a folder; flag the unresolvable ones",
          "--commit        # do it"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          github = GitHub.new
          tree = tree_for(options)
          changes = SpecPlanBuild::Resync::Prs.new(tree:, github:,
            adopt: options.fetch(:adopt, true), root: File.dirname(tree.dir))
            .call(commit: commit?(options))

          if changes.empty?
            success("Every pull request title already carries a prefix.") unless quiet?(options)
            return
          end

          changes.each do |change|
            puts "#{change.number}\t#{change.new_title || "-"}\t#{change.reason}"
          end

          return if quiet?(options)

          report_pr_changes(changes, options)
        rescue SpecPlanBuild::Error => e
          error(e.message)
          exit 69
        end

        private

        # @param changes [Array]
        # @param options [Hash]
        # @return [void]
        def report_pr_changes(changes, options)
          applicable, flagged = changes.partition(&:applicable?)
          assumed = applicable.select(&:assumed?)

          applicable.each do |c|
            note = if c.adopted? then paint("   (new plan)", :magenta)
            elsif c.assumed? then paint("   (assumed)", :yellow)
            end
            say("##{c.number}  #{c.new_title}#{note}")
          end

          report_adoptions(applicable.select(&:adopted?), options)

          flagged.each { |c| say("##{c.number}  #{paint("SKIPPED", :red)} — #{c.reason}", bullet: "!") }

          if commit?(options)
            success("Retitled #{applicable.size} pull request#{"s" unless applicable.size == 1}.")
          else
            dry_run_footer(applicable.size, "retitle#{"s" unless applicable.size == 1}")
          end

          return if assumed.empty?

          warn("#{assumed.size} title#{"s" unless assumed.size == 1} would get " \
                 "[#{SpecPlanBuild::NO_PLAN_PREFIX}] because no plan resolved.\n\n" \
                 "That is an assertion about intent, and it is yours to make: check each one\n" \
                 "before committing. A pull request that writes a plan's spec belongs to that\n" \
                 "plan however its branch was named.")
        end

        # Creating folders is a bigger act than editing a title, so it is
        # reported separately rather than buried in the retitle list.
        #
        # @param adopted [Array]
        # @param options [Hash]
        # @return [void]
        def report_adoptions(adopted, options)
          return if adopted.empty?

          verb = commit?(options) ? "Created" : "Would create"
          info("#{verb} #{adopted.size} plan folder#{"s" unless adopted.size == 1} for pull " \
               "requests that resolved to no plan:\n\n" \
               "#{adopted.map { |c| "  #{c.ordinal}  ##{c.number}  #{c.title}" }.join("\n")}\n\n" \
               "Each holds its pull request and nothing else. Run `spec-plan-build run --commit`\n" \
               "to have the specification written from what the pull request actually did.")
        end
      end
    end

    # `spec-plan-build linear …`
    module Linear
      # `linear import` — the plans, as Linear projects and issues.
      class Import < Base
        desc "Create Linear projects and issues from the plans, one per work unit"

        option :prefix, aliases: ["-p", "--team"],
          desc:            "The Linear team key that prefixes its issues, e.g. TAX"
        option :commit, type: :boolean, default: false,
          desc:          "Actually create and update in Linear (default: dry run)"
        option :format, default: "text", values: %w[text json],
          desc:          "json emits the exact arguments the Linear MCP tools take"
        option :since, aliases: ["-s"],
          desc:           "Skip plans numbered below this, e.g. 010.00"
        option :status,
          desc: "Only plans in these states: a comma-separated list of status keys"
        option :force, type: :boolean, default: false,
          desc:         "Update every issue, whether the plan has changed or not"

        example [
          "--prefix TAX                     # show what would be created",
          "--prefix TAX --commit            # do it, using LINEAR_API_KEY",
          "--prefix TAX --format json       # hand it to the MCP transport instead",
          "--prefix TAX --since 010.00      # only the recent plans",
          "--prefix TAX --status building,in_review"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          tree = tree_for(options)
          import = build(tree, options)

          return $stdout.puts(import.to_json) if options[:format] == "json"

          if import.pending.empty?
            success("Linear is already in step with #{tree.dir}.") unless quiet?(options)
            return
          end

          commit?(options) ? push(import, tree, options) : preview(import, options)
        rescue SpecPlanBuild::Error => e
          error(e.message)
          exit 69
        end

        private

        # @param tree [SpecPlanBuild::Tree]
        # @param options [Hash]
        # @return [SpecPlanBuild::Linear::Import]
        def build(tree, options)
          SpecPlanBuild::Linear::Import.new(tree:,
            team: SpecPlanBuild::Linear.key!(options[:prefix]),
            since: options[:since], statuses: statuses(options),
            force: options.fetch(:force, false))
        end

        # @param options [Hash]
        # @return [Array<Symbol>, nil]
        def statuses(options)
          return nil unless options[:status]

          options[:status].to_s.split(",").map { |word|
            SpecPlanBuild.status(word.strip)&.key ||
              raise(SpecPlanBuild::Error, "no such state: #{word.strip}")
          }
        end

        # @param import [SpecPlanBuild::Linear::Import]
        # @param options [Hash]
        # @return [void]
        def preview(import, options)
          import.pending.each { |action| puts row(action) }
          return if quiet?(options)

          import.pending.each { |action| say(line(action)) }
          report_unplaced(import)
          report_unattached(import)
          dry_run_footer(import.pending.size, "Linear change#{"s" unless import.pending.size == 1}")
          say_transport
        end

        # @param import [SpecPlanBuild::Linear::Import]
        # @param tree [SpecPlanBuild::Tree]
        # @param options [Hash]
        # @return [void]
        def push(import, tree, options)
          api = SpecPlanBuild::Linear::API.new(token: SpecPlanBuild::Linear::API.token_from_env)
          results = UI.spinning("Pushing #{import.pending.size} changes to Linear") {
            SpecPlanBuild::Linear::Push.new(import:, api:, tree:).call
          }

          done, failed = results.select { |r| r.action.pending? }.partition(&:ok?)
          done.each { |r| puts "#{r.action.op}\t#{r.identifier}\t#{r.action.title}" }
          return if quiet?(options)

          done.each { |r| say("#{paint(r.identifier.to_s, :green)}  #{r.action.title}") }
          failed.each { |r| say("#{paint("FAILED", :red)}  #{r.action.title} — #{r.error}", bullet: "!") }

          success("#{done.size} change#{"s" unless done.size == 1} pushed. " \
                  "Each plan's #{SpecPlanBuild::Linear::Issues::FILENAME} now records what it owns.")
          error("#{failed.size} change#{"s" unless failed.size == 1} did not land.") unless failed.empty?
        end

        # @param action [SpecPlanBuild::Linear::Action]
        # @return [String] the machine-readable line
        def row(action)
          [action.op, action.kind, action.ordinal, action.unit || "-",
            action.identifier || "-", action.title].join("\t")
        end

        # @param action [SpecPlanBuild::Linear::Action]
        # @return [String]
        def line(action)
          verb = paint(action.op.to_s.ljust(6), (action.op == :create) ? :green : :yellow)
          noun = (action.kind == :project) ? paint("project", :magenta) : "issue  "
          "#{verb} #{noun}  #{action.title}  #{paint("(#{action.reason})", :bright_black)}"
        end

        # @param import [SpecPlanBuild::Linear::Import]
        # @return [void]
        def report_unplaced(import)
          return if import.unplaced.empty?

          listed = import.unplaced.map { |status, ordinals|
            "  #{status} — #{ordinals.join(", ")}\n" +
              wrapped(SpecPlanBuild::Linear.reason_unplaced(status))
          }
          warn("Not imported, because nothing here knows where they belong:\n\n" \
               "#{listed.join("\n\n")}\n\n" \
               "Decide where they go on your board and add it to Linear::PLACEMENTS. " \
               "Filing them somewhere plausible would be worse than leaving them out.")
        end

        # A box re-wraps a line that overruns it, and the wrapped remainder
        # comes back at column zero — which reads as a new entry rather than
        # the continuation of one. Wrapping it here keeps the indent.
        #
        # @param text [String]
        # @param width [Integer] narrower than the narrowest box
        # @return [String]
        def wrapped(text, width: 58)
          text.split.each_with_object([+""]) { |word, lines|
            lines << +"" if lines.last.length + word.length + 1 > width
            lines.last << " " unless lines.last.empty?
            lines.last << word
          }.map { |line| "    #{line}" }.join("\n")
        end

        # @param import [SpecPlanBuild::Linear::Import]
        # @return [void]
        def report_unattached(import)
          return if import.unattached.empty?

          listed = import.unattached.map { |ordinal, prs|
            "  #{ordinal}  #{prs.map(&:label).join("\n            ")}"
          }
          warn("These pull requests name no work unit their plan declares, so no issue " \
               "claims them:\n\n#{listed.join("\n")}\n\n" \
               "They are listed on the project instead. Either the plan is missing a unit, " \
               "or the pull request title is missing its PR-n.")
        end

        # @return [void]
        def say_transport
          return if SpecPlanBuild::Linear::API.token_from_env

          info("--commit needs #{SpecPlanBuild::Linear::API::TOKEN_VARIABLE} in the environment.\n\n" \
               "Without it, drive the same plan through the Linear MCP server instead:\n\n" \
               "  spec-plan-build linear import --prefix <KEY> --format json\n\n" \
               "and hand the result to /plan-linear-import, which calls save_project and\n" \
               "save_issue with those arguments verbatim.")
        end
      end
    end

    # `spec-plan-build docs` — regenerate the conventions document.
    class Docs < Base
      desc "Generate the conventions document from the state machine itself"

      option :output, aliases: ["-o"], desc: "Write here instead of STDOUT", default: "context/feature-building/spec-plan-build.md"

      example ["", "-o tentative-new-plan.md"]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        document = Documentation.new.render

        if (path = options[:output])
          File.write(path, document)
          success("Wrote #{path}") unless quiet?(options)
        else
          $stdout.write(document)
        end
      end
    end

    # `spec-plan-build run` — drive the specialist agents until the tree settles.
    class Run < Base
      desc "Run specialist agents over the plans until nothing changes"

      option :commit, type: :boolean, default: false,
        desc:          "Actually invoke the agents (default: dry run, prints the plan of work)"
      option :rounds, default: "10", desc: "Hard ceiling on loop iterations"
      option :agent, desc: "Only run this one agent"
      option :root, desc: "Repository root the agents work in (default: the .plans parent)"
      option :isolation, default: "worktree", values: %w[worktree shared],
        desc:                "worktree: a checkout and branch per plan, run in parallel. shared: one tree, serial"
      option :jobs, aliases: ["-j"],
        desc:           "Agents to run at once (default: cores - 2, capped at 12)"
      option :push_pr, aliases: ["-p"],
        desc:              "Push each finished branch and open a PR titled [NNN.MM](X). " \
                             "Pass a letter to force it; omit to continue the plan's sequence. Requires --commit"

      example [
        "                       # show which agent would take which plan",
        "--commit               # run them, one worktree per plan, in parallel",
        "--commit -j 4          # …with four at a time",
        "--isolation shared     # one tree, serial — no git required",
        "--commit --rounds 3    # …with a tighter ceiling"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        tree = tree_for(options)
        root = options[:root] || File.dirname(tree.dir)
        agents = Agents.new
        agents = filtered(agents, options[:agent]) if options[:agent]

        isolation = options.fetch(:isolation, "worktree").to_sym
        jobs = (options[:jobs] || UI.default_jobs).to_i

        if isolation == :worktree && !Worktree.new(root:).repository?
          error("#{root} is not a git repository, so plans cannot be isolated.\n\n" \
                  "Run with --isolation shared to work in one tree, serially.")
          exit 66
        end

        runner = Runner.new(
          tree:, agents:, isolation:, jobs:,
          worktree: (Worktree.new(root:) if isolation == :worktree),
          max_rounds: options.fetch(:rounds, 10).to_i,
          executor: Executor.new(root:, dry_run: !commit?(options))
        )

        rounds = runner.call
        report(runner, rounds, options)
        publish(runner, root, options) if options.key?(:push_pr)
        exit(failures(rounds).empty? ? 0 : 1)
      end

      private

      # @param agents [SpecPlanBuild::Agents]
      # @param name [String]
      # @return [SpecPlanBuild::Agents]
      def filtered(agents, name)
        agents.find(name) or begin
          error("No agent called #{name}.\n\nKnown: #{agents.all.map(&:name).join(", ")}")
          exit 65
        end
        agents
      end

      # @param rounds [Array]
      # @return [Array]
      def failures(rounds) = rounds.flat_map(&:attempts).reject(&:ok)

      # Push finished branches and open their pull requests.
      #
      # This is the only thing the harness does that leaves the machine, so it
      # is refused unless isolation gave each plan its own branch, and unless
      # --commit says the caller means it.
      #
      # @param runner [SpecPlanBuild::Runner]
      # @param root [String]
      # @param options [Hash]
      # @return [void]
      def publish(runner, root, options)
        unless runner.isolated?
          error("--push-pr needs one branch per plan.\n\nRe-run without --isolation shared.")
          exit 64
        end

        # "auto" is what the entry script fills in for a bare --push-pr.
        letter = options[:push_pr].to_s.strip
        letter = nil if letter.empty? || letter.casecmp?("auto")
        publisher = Publisher.new(root:, dry_run: !commit?(options))

        published = runner.tree.reload.subjects.filter_map do |subject|
          checkout = runner.worktree.checkout_for(subject.feature)
          next unless checkout.dirty?

          publisher.publish(checkout:, subject:, letter:)
        end

        published.each { |p| puts "#{p.ordinal}\t#{p.branch}\t#{p.title}\t#{p.url || p.refusal || "would open"}" }
        return if quiet?(options) || published.empty?

        opened, refused = published.partition(&:published?)
        lines = published.map { |p| "  #{p.title}#{"\n    #{p.url}" if p.url}#{" — #{p.refusal}" if p.refusal}" }

        if !commit?(options)
          warn("Would push #{published.size} branch#{"es" unless published.size == 1} and open pull requests:\n" +
               lines.join("\n") + "\n\nRe-run with --commit.")
        elsif refused.empty?
          success("Opened #{opened.size} pull request#{"s" unless opened.size == 1}:\n" + lines.join("\n"))
        else
          warn("#{opened.size} opened, #{refused.size} refused:\n" + lines.join("\n"))
        end
      end

      # @param runner [SpecPlanBuild::Runner]
      # @param rounds [Array]
      # @param options [Hash]
      # @return [void]
      def report(runner, rounds, options)
        rounds.each do |round|
          puts "round #{round.number}"
          round.attempts.each do |a|
            mark = if !a.ok
              "FAIL"
            elsif a.advanced?
              "#{a.from} -> #{a.to}"
            else
              "no change"
            end
            puts "  #{a.ordinal}\t#{a.agent}\t#{mark}\t#{a.note}"
          end
        end

        return if quiet?(options)

        advanced = rounds.sum(&:advanced)
        blocked = runner.blocked
        summary = ["#{rounds.size} round#{"s" unless rounds.size == 1}", "#{advanced} advanced"]
        summary << (runner.isolated? ? "#{runner.jobs} at a time, one worktree each" : "serial, shared tree")
        summary << "#{blocked.size} blocked" unless blocked.empty?
        summary << "#{failures(rounds).size} failed" unless failures(rounds).empty?

        if !commit?(options)
          warn("Dry run — no agent was invoked.\n#{summary.join(" · ")}\n\nRe-run with --commit.")
        elsif failures(rounds).empty?
          success("#{summary.join(" · ")}#{"\n\nEvery plan is done or deliberately parked." if runner.settled?}")
        else
          error("#{summary.join(" · ")}\n\n#{failures(rounds).map { |f| "#{f.ordinal} #{f.agent}: #{f.note}" }.join("\n")}")
        end

        return if blocked.empty?

        warn("#{blocked.size} plan#{"s" unless blocked.size == 1} need a human decision:\n" +
             blocked.map { |b| "  #{b.feature.ordinal} #{b.status.emoji} #{b.feature.title} — see blocked.md" }.join("\n"))
      end
    end

    # `spec-plan-build version`
    class Version < Dry::CLI::Command
      desc "Print the version and exit"

      # @return [void]
      def call(**) = puts("spec-plan-build #{SpecPlanBuild::VERSION}")
    end

    register "create", Create, aliases: %w[new c]
    register "status", Status, aliases: %w[st]
    register "run", Run
    register "docs", Docs
    register "index", Index, aliases: %w[idx]
    register "version", Version, aliases: %w[--version -v]

    register "resync" do |prefix|
      prefix.register "dirs", Resync::Dirs
      prefix.register "prs", Resync::Prs
    end

    register "linear" do |prefix|
      prefix.register "import", Linear::Import
    end
  end
end
