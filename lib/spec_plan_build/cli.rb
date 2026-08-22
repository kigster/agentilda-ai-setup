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
          desc: "The .plans directory"
        klass.option :quiet, type: :boolean, default: false, aliases: ["-q"],
          desc: "Suppress progress output on STDERR"
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
        desc: "The topic, two to five words; becomes the folder slug"

      option :after, aliases: ["-a"],
        desc: "Create a retroactive plan in the gap after this plan, e.g. 002"
      option :status, aliases: ["-s"],
        desc: "Open in a state other than the default"
      option :prs, aliases: ["--pr"],
        desc: "Document work that already shipped: pull request numbers or URLs, comma separated. Requires --after"
      option :spec, type: :boolean, default: true,
        desc: "With --prs, write spec.md from what the pull requests did. --no-spec records them and stops, which is fast and offline"
      option :draft, type: :boolean, default: true,
        desc: "For a new feature (no --prs), attempt spec.md's four headings from project context via `claude`. --no-draft leaves them bare"
      option :open, type: :boolean, default: true,
        desc: "Open the new spec.md in the system editor when done (macOS `open`). --no-open leaves it for you to open"

      # noinspection RubyMismatchedArgumentType
      example [
        "tax rule dsl                        # 003.00-⚪️-tax-rule-dsl, spec.md scaffolded and drafted",
        "tax rule dsl --no-draft --no-open   # scaffold only, nothing shelled out, nothing opened",
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

      # A plan with recorded pull requests already has its facts — hand it to
      # the writer that reconstructs a specification from a diff. One without
      # them does not exist yet, and reconstructing is not the job; {#brief} is.
      #
      # @param path [String]
      # @param prs [Array<Hash>, nil]
      # @param options [Hash]
      # @return [void]
      def created(path, prs, options)
        from_prs = prs && !prs.empty?
        path = if from_prs
                 synthesize(path, options) if options.fetch(:spec, true)
               else
                 brief(path, options)
        end || path
        puts path
        return if quiet?(options)

        feature = Feature.parse(path)
        success("Created #{File.basename(path)}\n\n" \
        "#{feature.status.emoji} #{feature.status.label} — #{feature.status.note}\n" \
        "#{next_step(path, feature, from_prs:)}")
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

      # A folder with no pull requests to reconstruct from is a feature that
      # does not exist yet. {Brief} writes the four headings a human still has
      # to answer, makes a best-effort pass at them from what the project
      # already has on disk, and — unless told not to — opens the result for
      # a human to finish. The folder's state never moves: ⚪️ New only ever
      # claimed that a specification exists, not that it is complete.
      #
      # @param path [String]
      # @param options [Hash]
      # @return [String] +path+, unchanged
      def brief(path, options)
        feature = Feature.parse(path)
        return path if feature.status.key == :retroactive

        root = options[:root] || File.dirname(path, 2)
        brief = Brief.new(path:, title: feature.title, root:)
        brief.write_scaffold!

        if options.fetch(:draft, true)
          ok, note = UI.spinning("Drafting spec.md from project context") { brief.attempt! }
          warn_about_draft(note) unless ok
        end

        open_spec(brief.spec_path) if options.fetch(:open, true)
        path
      end

      # @param spec_path [String]
      # @return [void]
      def open_spec(spec_path)
        return unless RbConfig::CONFIG["host_os"].to_s.match?(/darwin/)

        system("open", spec_path, out: File::NULL, err: File::NULL)
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

      # @param note [String]
      # @return [void]
      def warn_about_draft(note)
        error("spec.md was scaffolded, but the drafting attempt did not finish:\n#{note}\n\n" \
              "The four headings are there, empty. Fill them in by hand, or hand off to leah-researcher.")
      end

      # @param path [String]
      # @param feature [SpecPlanBuild::Feature]
      # @return [String]
      def next_step(path, feature, from_prs:)
        spec = File.join(File.basename(path), "spec.md")
        return "Next: write #{spec}" unless feature.status.key == :new && File.file?(File.join(path, "spec.md"))
        return "Next: read #{spec} — it was written from the pull requests, so check it against what actually shipped" if from_prs

        "Next: fill in the four headings in #{spec}, then hand off to leah-researcher"
      end
    end

    # `spec-plan-build index` — the plans as one browsable page.
    class Index < Base
      desc "Write .plans/INDEX.md: every plan, its goal, its pull requests and its documents"

      option :output, aliases: ["-o"],
        desc: "Write somewhere other than <plans>/INDEX.md; - for STDOUT"
      option :project, aliases: ["-p"],
        desc: "Heading for the page, default: the repository's directory name"

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
          desc: "Actually rename the folders (default: dry run)"

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
          desc: "Actually retitle the pull requests (default: dry run)"
        option :state, default: "all", values: %w[open closed merged all],
          desc: "Which pull requests to consider"
        option :adopt, type: :boolean, default: true,
          desc: "Mint a retroactive plan folder for every pull request that resolves to none. --no-adopt flags them for a human instead"

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
            note = if c.adopted?
              paint("   (new plan)", :magenta)
            elsif c.assumed?
              paint("   (assumed)", :yellow)
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
      # Shared by both linear commands: the team is which workspace this is
      # about, so it is an argument rather than a flag. There is no default —
      # a tool that picks a team for you when you forget to say which is a
      # tool that files a quarter of somebody's work in the wrong place.
      class Team < Base
        def self.inherited(klass)
          super
          klass.argument :team, required: true,
            desc: "The Linear team key that prefixes its issues, e.g. TAX"
        end

        private

        # The key is checked before anything reaches for a token, so a typo in
        # the team name reports the typo rather than an authentication
        # problem the user does not have.
        #
        # @param team [String]
        # @return [SpecPlanBuild::Linear::Survey]
        def survey_for(team, tree)
          key = SpecPlanBuild::Linear.key!(team)
          api = SpecPlanBuild::Linear::API.new(token: SpecPlanBuild::Linear::API.token_from_env)
          projects = UI.spinning("Listing #{key} projects") { api.projects(api.team(key)[:id]) }
          [api, SpecPlanBuild::Linear::Survey.new(tree:, projects:)]
        end
      end

      # `linear projects` — what the team already has.
      class Projects < Team
        desc "List the Linear projects a team owns, and which plans they already cover"

        example [
          "TAX        # every project the team owns, matched against .plans"
        ]

        # @param team [String]
        # @param options [Hash]
        # @return [void]
        def call(team:, **options)
          tree = tree_for(options)
          _api, survey = survey_for(team, tree)

          survey.projects.each { |project| puts row(project) }
          return if quiet?(options)

          survey.projects.each do |project|
            say("#{paint(project["name"], :cyan)}\n    #{paint(project["url"].to_s, :bright_black)}")
          end
          report_descriptions(survey)
        rescue SpecPlanBuild::Error => e
          error(e.message)
          exit 69
        end

        private

        # @param project [Hash]
        # @return [String]
        def row(project)
          [project["name"], project.dig("status", "name") || "-", project["url"]].join("\t")
        end

        # @param survey [SpecPlanBuild::Linear::Survey]
        # @return [void]
        def report_descriptions(survey)
          return if survey.undescribed.empty?

          warn("#{survey.undescribed.size} of these say nothing about themselves:\n\n" \
               "#{survey.undescribed.map { |p| "  #{p["name"]}" }.join("\n")}\n\n" \
               "A name is three or four words and half of them are the company's. If you " \
               "want anything here to reason about which project a plan belongs to, that " \
               "reasoning has to have a sentence to read.")
        end
      end

      # `linear import` — the plans, as Linear issues under one of your projects.
      class Import < Team
        desc "Create Linear issues from the plans: one per folder, one child per work unit"

        option :project, aliases: ["-p", "--project-url", "--project-id"],
          desc: "The project to file everything under: its URL, its name, or its id"
        option :commit, type: :boolean, default: false,
          desc: "Actually create and update in Linear (default: dry run)"
        option :format, default: "text", values: %w[text json],
          desc: "json emits the exact arguments the Linear MCP tools take"
        option :since, aliases: ["-s"],
          desc: "Skip plans numbered below this, e.g. 010.00"
        option :status,
          desc: "Only plans in these states: a comma-separated list of status keys"
        option :force, type: :boolean, default: false,
          desc: "Update everything, whether the plan has changed or not"

        example [
          "TAX -p 'US Tax Law: Self Contained Ruby Gem'   # show what would be created",
          "TAX -p https://linear.app/acme/project/…       # a URL works too",
          "TAX -p 'Ruby Gem' --commit                     # do it, using LINEAR_API_KEY",
          "TAX -p 'Ruby Gem' --format json                # hand it to the MCP transport instead",
          "TAX -p 'Ruby Gem' --since 010.00               # only the recent plans",
          "TAX -p 'Ruby Gem' --status building,in_review"
        ]

        # @param team [String]
        # @param options [Hash]
        # @return [void]
        def call(team:, **options)
          tree = tree_for(options)
          require_project!(options)
          import = build(tree, team, resolve_project(team, tree, options), options)

          return $stdout.puts(import.to_json) if options[:format] == "json"

          if import.pending.empty?
            success("Linear is already in step with #{tree.dir}.") unless quiet?(options)
            return
          end

          preview(import, options)
        rescue SpecPlanBuild::Error => e
          error(e.message)
          exit 69
        end

        private

        # Looking the project up costs a token, and the whole point of
        # `--format json` is to work without one. A name needs no lookup — the
        # MCP server resolves a project by name itself — so only a URL or an
        # id, which do not carry a name, force the network.
        #
        # @return [Hash] `{"id", "name", "url"}`
        def resolve_project(team, tree, options)
          reference = options[:project].to_s
          looks_up = reference.match?(%r{\Ahttps?://}) || reference.match?(/\A[0-9a-f-]{32,}\z/)
          return {"id" => nil, "name" => reference, "url" => nil} if !looks_up && offline?

          _api, survey = survey_for(team, tree)
          survey.project(reference)
        end

        # @return [Boolean]
        def offline? = SpecPlanBuild::Linear::API.token_from_env.nil?

        # @param options [Hash]
        # @return [void]
        def require_project!(options)
          return if options[:project]

          raise SpecPlanBuild::Error,
            "which project? Pass -p with a project's URL, name or id.\n\n" \
            "This never creates one: a team's project list is something you curated, and " \
            "every plan is filed under one you named.\n\n" \
            "  spec-plan-build linear projects <TEAM>   lists them"
        end

        # @return [SpecPlanBuild::Linear::Import]
        def build(tree, team, project, options)
          SpecPlanBuild::Linear::Import.new(tree:, team: SpecPlanBuild::Linear.key!(team), project:,
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
          dry_run_footer(import.pending.size, "Linear change#{"s" unless import.pending.size == 1}")
        end

        # @param action [SpecPlanBuild::Linear::Action]
        # @return [String]
        def row(action)
          [action.op, action.kind, action.ordinal, action.unit || "-",
            action.identifier || "-", action.title].join("\t")
        end

        # @param action [SpecPlanBuild::Linear::Action]
        # @return [String]
        def line(action)
          verb = paint(action.op.to_s.ljust(6), (action.op == :create) ? :green : :yellow)
          indent = action.child? ? "    " : ""
          "#{verb} #{indent}#{action.title}  #{paint("(#{action.reason})", :bright_black)}"
        end

        # @param import [SpecPlanBuild::Linear::Import]
        # @return [void]
        def report_unplaced(import)
          return if import.unplaced.empty?

          listed = import.unplaced.map { |status, ordinals|
            "  #{status} — #{ordinals.join(", ")}\n#{wrapped(SpecPlanBuild::Linear.reason_unplaced(status))}"
          }
          warn("Not imported, because nothing here knows where they belong:\n\n" \
               "#{listed.join("\n\n")}\n\n" \
               "Decide where they go on your board and add it to Linear::PLACEMENTS.")
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
          system("command -v mdformat >/dev/null 2>&1 && mdformat --wrap no #{path}")
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
        desc: "Actually invoke the agents (default: dry run, prints the plan of work)"
      option :rounds, default: "10", desc: "Hard ceiling on loop iterations"
      option :agent, desc: "Only run this one agent"
      option :plan, aliases: ["--plans"],
        desc: "Only these plans, comma separated: NNN or NNN.MM, e.g. --plan 003,005.01. Default: the whole tree"
      option :root, desc: "Repository root the agents work in (default: the .plans parent)"
      option :isolation, default: "worktree", values: %w[worktree shared],
        desc: "worktree: a checkout and branch per plan, run in parallel. shared: one tree, serial"
      option :jobs, aliases: ["-j"],
        desc: "Agents to run at once (default: cores - 2, capped at 12)"
      option :dont_push_anything, type: :boolean, default: false,
        desc: "With --commit and --isolation worktree, a finished branch is pushed and its pull request " \
        "opened as soon as it lands, titled [NNN.MM](X). Pass this to turn that off and leave it uncommitted."
      option :log, desc: "Append progress to this file (default: a per-project file under the system temp dir)"

      example [
        "                       # show which agent would take which plan",
        "--commit               # run them, one worktree per plan, in parallel",
        "--commit -j 4          # …with four at a time",
        "--isolation shared     # one tree, serial — no git required",
        "--commit --rounds 3    # …with a tighter ceiling",
        "--commit --plan 005,006,007  # only the plans a batch step just created"
      ]

      # @param options [Hash]
      # @return [void]
      def call(**options)
        tree = tree_for(options)
        root = options[:root] || File.dirname(tree.dir)
        agents = Agents.new
        agents = filtered(agents, options[:agent]) if options[:agent]
        plans = options[:plan] ? scoped(tree, options[:plan]) : nil

        isolation = options.fetch(:isolation, "worktree").to_sym
        jobs = (options[:jobs] || UI.default_jobs).to_i

        if isolation == :worktree && !Worktree.new(root:).repository?
          error("#{root} is not a git repository, so plans cannot be isolated.\n\n" \
          "Run with --isolation shared to work in one tree, serially.")
          exit 66
        end

        # Set before the loop starts, not after: `UI.animate?` (and therefore
        # whether a round prints anything at all) is read the whole time the
        # loop runs, not just when `report` prints its closing summary.
        quiet?(options)
        UI.log_path = options[:log] || File.join(Dir.tmpdir, "spec-plan-build-#{File.basename(root)}.log")
        info("Progress: #{UI.log_path}") unless quiet?(options)

        runner = Runner.new(
          tree:, agents:, isolation:, jobs:, plans:,
          worktree: (Worktree.new(root:) if isolation == :worktree),
          max_rounds: options.fetch(:rounds, 10).to_i,
          executor: Executor.new(root:, dry_run: !commit?(options)),
          publisher: publisher_for(root, isolation, options)
        )

        rounds = runner.call
        report(runner, rounds, options)
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

      # `--plan` names the whole point of scoping: a skill that just minted
      # N folders hands off exactly those, not the tree. A typo'd or already-
      # settled number silently running the whole tree instead is the failure
      # this exists to prevent, so an unknown one is refused rather than
      # dropped.
      #
      # @param tree [SpecPlanBuild::Tree]
      # @param text [String]
      # @return [Array<SpecPlanBuild::Ordinal>]
      def scoped(tree, text)
        known = tree.subjects.map { |s| s.feature.ordinal }
        text.split(",").map(&:strip).reject(&:empty?).map { |token|
          ordinal = Ordinal.parse(token)
          unless ordinal && known.include?(ordinal)
            error("No plan #{token} in #{tree.dir}.\n\n" \
                  "Known: #{known.join(", ")}")
            exit 66
          end
          ordinal
        }
      end

      # @param rounds [Array]
      # @return [Array]
      def failures(rounds) = rounds.flat_map(&:attempts).reject(&:ok)

      # The one thing this harness does that leaves the machine — pushing a
      # branch and opening its pull request — so it takes one more thing to
      # turn on than everything else here: `--commit` alone is not enough,
      # isolation has to actually give each plan a branch of its own too.
      #
      # `nil` is how {Runner} is told to leave a finished worktree alone; it
      # is what `--dont-push-anything` asks for, and what a shared tree gets
      # by construction, since there is no separate branch there to push.
      #
      # @param root [String]
      # @param isolation [Symbol]
      # @param options [Hash]
      # @return [SpecPlanBuild::Publisher, nil]
      def publisher_for(root, isolation, options)
        return nil if isolation != :worktree || options[:dont_push_anything]

        Publisher.new(root:, dry_run: !commit?(options))
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
             blocked.map { |b| "  #{b.feature.ordinal} #{b.status.emoji} #{b.feature.title} — see blocked.md" }.join("\n") +
             "\n\nWrite the answers into blocked.md, then: spec-plan-build unblock " \
             "#{blocked.map { |b| b.feature.ordinal }.join(",")} --commit")
      end
    end

    # `spec-plan-build unblock NNN…` — hand a stopped plan to the agent that
    # drains its `blocked.md`.
    #
    # Deliberately not part of `run`. ⭕️ and 🅱️ are {StateMachine::SETTLED}, so
    # the loop never offers a blocked plan to anybody, and that is the property
    # that makes the state mean anything: the plan waits for a human, and no
    # agent quietly decides otherwise. Answers arriving is not a fact the tool
    # can observe, so a human typing this command *is* the signal, and there is
    # nothing else that could produce it.
    class Unblock < Base
      # The agent that knows the shape of `blocked.md`.
      DEFAULT_AGENT = "lando-broker"

      # The two states with a `blocked.md` to drain.
      BLOCKED = %i[blocked product_blocked].freeze

      desc "Fold answered blocks into a plan's documents and retire blocked.md"

      argument :plans, type: :array, required: true,
        desc: "Which plans to drain: NNN or NNN.MM, e.g. 003 005.01"

      option :commit, type: :boolean, default: false,
        desc: "Actually invoke the agent (default: dry run, prints the questions still open)"
      option :agent, default: DEFAULT_AGENT, desc: "Hand the folder to a different agent"
      option :root, desc: "Repository root the agent works in (default: the .plans parent)"

      example [
        "003                # what 003 is still waiting on",
        "003 --commit       # fold in whatever has been answered",
        "003,005 --commit   # both"
      ]

      # @param plans [Array<String>]
      # @param options [Hash]
      # @return [void]
      def call(plans:, **options)
        tree = tree_for(options)
        root = options[:root] || File.dirname(tree.dir)
        agent = agent_for(options)
        subjects = targets(tree, plans)
        quiet?(options)

        executor = Executor.new(root:, dry_run: !commit?(options))
        results = subjects.map { |subject| [subject, *executor.call(agent, subject, root:)] }

        # The same pass the loop makes after every round, for the same reason:
        # a drained folder is only *named* differently once something reads the
        # file the agent just deleted.
        SpecPlanBuild::Resync::Dirs.new(tree:).call(commit: true) if commit?(options)

        report(tree, results, options)
        exit((results.all? { |(_, ok, _)| ok }) ? 0 : 1)
      end

      private

      # @param options [Hash]
      # @return [SpecPlanBuild::Agent]
      def agent_for(options)
        name = options.fetch(:agent, DEFAULT_AGENT)
        agents = Agents.new
        agents.find(name) or begin
          error("No agent called #{name}.\n\nKnown: #{agents.all.map(&:name).join(", ")}")
          exit 65
        end
      end

      # A plan that is not blocked is refused, not skipped. Whoever typed this
      # believes an answer has arrived; running against a folder that was never
      # stopped and saying nothing is how you come back later to a plan nobody
      # touched and no record of why.
      #
      # @param tree [SpecPlanBuild::Tree]
      # @param plans [Array<String>]
      # @return [Array<SpecPlanBuild::Subject>]
      def targets(tree, plans)
        tokens = plans.flat_map { |token| token.split(",") }.map(&:strip).reject(&:empty?)

        tokens.map do |token|
          subject = tree.find(token) or begin
            error("No plan #{token} in #{tree.dir}.\n\nKnown: #{tree.ordinals.join(", ")}")
            exit 66
          end
          next subject if BLOCKED.include?(subject.status.key)

          error("#{subject.feature.ordinal} is #{subject.status}, not blocked.\n\n" \
                "Only ⭕️ and 🅱️ folders have a blocked.md to drain.")
          exit 65
        end
      end

      # What `blocked.md` still names, written as the file writes it. This is
      # the whole of the dry run, and the whole of what a human is on the hook
      # for afterwards.
      #
      # @param subject [SpecPlanBuild::Subject]
      # @return [Array<String>]
      def open_questions(subject)
        subject.read("blocked.md").to_s.lines.grep(SpecPlanBuild::OPEN_BLOCK)
          .map { |line| line.strip.sub(/\A\#+[ \t]*/, "") }
      end

      # @param tree [SpecPlanBuild::Tree]
      # @param results [Array<Array>] subject, ok, note
      # @param options [Hash]
      # @return [void]
      def report(tree, results, options)
        tree.reload

        rows = results.map { |subject, ok, note|
          current = tree.find(subject.feature.ordinal) || subject
          [current, ok, note, open_questions(current)]
        }

        rows.each do |current, ok, note, questions|
          puts "#{current.feature.ordinal}\t#{ok ? current.status.key : "failed"}\t#{questions.size} open\t#{note}"
          next if quiet?(options)

          say("#{paint(current.feature.ordinal.to_s, :bright_black)} #{current.status.emoji} #{current.feature.title}")
          if questions.empty?
            say("  #{paint("nothing left open", :green)}", bullet: " ")
          else
            questions.each { |question| say("  #{paint(question, :yellow)}", bullet: " ") }
          end
        end

        footer(rows, options) unless quiet?(options)
      end

      # @param rows [Array<Array>] current subject, ok, note, open questions
      # @param options [Hash]
      # @return [void]
      def footer(rows, options)
        failed = rows.reject { |(_, ok, _, _)| ok }

        unless commit?(options)
          warn("Dry run: no agent was invoked.\nRe-run with --commit to fold in whatever has been answered.")
          return
        end

        unless failed.empty?
          error(failed.map { |(current, _, note, _)| "#{current.feature.ordinal}: #{note}" }.join("\n"))
          return
        end

        cleared = rows.count { |(current, _, _, _)| !current.file?("blocked.md") }
        waiting = rows.size - cleared
        success("#{cleared} unblocked · #{waiting} still waiting on a human.")
      end
    end

    # `spec-plan-build version`
    class Version < Dry::CLI::Command
      desc "Print the version and exit"

      # @return [void]
      def call(**) = puts("spec-plan-build #{SpecPlanBuild::VERSION}")
    end

    # `spec-plan-build states` — the state machine, as a terminal diagram.
    class States < Dry::CLI::Command
      desc "Print a diagram of every state and the transitions between them"

      example [""]

      # @return [void]
      def call(**) = $stdout.write(Diagram.new.render)
    end

    register "create", Create, aliases: %w[new c]
    register "status", Status, aliases: %w[st]
    register "run", Run
    register "unblock", Unblock
    register "docs", Docs
    register "states", States, aliases: %w[diagram]
    register "index", Index, aliases: %w[idx]
    register "version", Version, aliases: %w[--version -v]

    register "resync" do |prefix|
      prefix.register "dirs", Resync::Dirs
      prefix.register "prs", Resync::Prs
    end

    register "linear" do |prefix|
      prefix.register "import", Linear::Import
      prefix.register "projects", Linear::Projects
    end
  end
end
