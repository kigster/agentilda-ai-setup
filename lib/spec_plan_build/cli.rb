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

      # noinspection RubyMismatchedArgumentType
      example [
        "tax rule dsl                  # 003.00-⚪️-tax-rule-dsl",
        "--after 002 schedule k1       # 002.01-⬜️-schedule-k1 (documented after the fact)",
        "--status ready billing sync   # opens at ⭐️ instead of ⚪️"
      ]

      # @param words [Array<String>]
      # @param options [Hash]
      # @return [void]
      def call(words:, **options)
        dir = options.fetch(:dir, SpecPlanBuild::PLANS_DIR)
        FileUtils.mkdir_p(dir)

        result = Creator.new(dir:).create(words:, after: options[:after], status: options[:status])

        result.either(
          lambda { |path|
            puts path
            unless quiet?(options)
              feature = Feature.parse(path)
              success("Created #{File.basename(path)}\n\n" \
                        "#{feature.status.emoji} #{feature.status.label} — #{feature.status.note}\n" \
                        "Next: write #{File.join(File.basename(path), "spec.md")}")
            end
          },
          lambda { |message|
            error("Could not create the plan:\n#{message}")
            exit 65
          }
        )
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
      # `resync dirs` — reconcile folder emoji with folder contents.
      class Dirs < Base
        desc "Rename plan folders so their emoji matches their contents"

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
            success("Every folder's emoji already matches its contents.") unless quiet?(options)
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

        example [
          "                # show what would be retitled",
          "--state open    # only open pull requests",
          "--commit        # do it"
        ]

        # @param options [Hash]
        # @return [void]
        def call(**options)
          github = GitHub.new
          changes = SpecPlanBuild::Resync::Prs.new(tree: tree_for(options), github:)
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
            say("##{c.number}  #{c.new_title}#{paint("   (assumed)", :yellow) if c.assumed?}")
          end

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
    register "version", Version, aliases: %w[--version -v]

    register "resync" do |prefix|
      prefix.register "dirs", Resync::Dirs
      prefix.register "prs", Resync::Prs
    end
  end
end
