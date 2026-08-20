# frozen_string_literal: true

require "json"

module SpecPlanBuild
  module Linear
    # One thing that would happen in Linear.
    #
    # `args` is deliberately shaped as the Linear MCP server's `save_project`
    # and `save_issue` arguments, because that server addresses everything by
    # the names a human already knows — a team by its key, a project by its
    # name, a workflow state by its name, an issue by its identifier. Emitting
    # exactly that shape means the JSON this produces can drive either
    # transport unchanged: {Push} turns it into GraphQL, and the skill hands
    # it to the MCP tools as-is. One contract, so the two cannot drift.
    #
    # @!attribute [r] kind
    #   @return [Symbol] `:project` or `:issue`
    # @!attribute [r] op
    #   @return [Symbol] `:create`, `:update` or `:skip`
    # @!attribute [r] ordinal
    #   @return [String] the plan this belongs to, e.g. "003.00"
    # @!attribute [r] unit
    #   @return [String, nil] the {Unit#key}, nil for a project
    # @!attribute [r] identifier
    #   @return [String, nil] what Linear already calls it, when it exists
    # @!attribute [r] title
    #   @return [String] for the human reading the dry run
    # @!attribute [r] digest
    #   @return [String] fingerprint of `args`, recorded after a push
    # @!attribute [r] args
    #   @return [Hash] the MCP argument shape
    # @!attribute [r] reason
    #   @return [String] why this operation and not another
    Action = Data.define(:kind, :op, :ordinal, :unit, :identifier, :title, :digest, :args, :reason) do
      # @return [Boolean] whether this would change anything
      def pending? = op != :skip

      # @return [Hash] for `--format json`
      def to_h_json
        {kind:, op:, plan: ordinal, unit:, identifier:, title:, digest:, args:}.compact
      end
    end

    # What a plan folder would become in Linear, and what has already become
    # of it. Reads the filesystem; touches nothing else.
    #
    # Keeping the whole decision offline is what makes `--commit` honest. The
    # dry run is not an approximation of what a push would do — it is the same
    # object the push consumes, so what gets printed and what gets sent cannot
    # disagree.
    class Import
      # @param tree [SpecPlanBuild::Tree]
      # @param team [String] the team key, e.g. "TAX"
      # @param since [String, nil] skip plans numbered below this
      # @param statuses [Array<Symbol>, nil] only these states
      # @param force [Boolean] update every issue, matching digest or not
      def initialize(tree:, team:, since: nil, statuses: nil, force: false)
        @tree = tree
        @team = team.to_s.strip.upcase
        @since = since && Ordinal.parse(since)
        @statuses = statuses
        @force = force
      end

      # @return [String] the team key
      attr_reader :team

      # @return [Array<SpecPlanBuild::Linear::Action>] in plan order
      def actions = @actions ||= subjects.flat_map { |s| actions_for(s) }

      # @return [Array<SpecPlanBuild::Linear::Action>]
      def pending = actions.select(&:pending?)

      # @return [String] the whole import, for a pipe
      def to_json(*_args)
        JSON.pretty_generate(team:, actions: actions.map(&:to_h_json))
      end

      # Plans in a state nobody has decided how to file, and why not.
      #
      # They are reported rather than dropped quietly, and rather than filed
      # somewhere plausible. An issue in the wrong column reads exactly like
      # an issue in the right one, and nobody goes looking for a mistake that
      # renders correctly.
      #
      # @return [Hash{SpecPlanBuild::Status => Array<String>}] state => ordinals
      def unplaced
        @unplaced ||= (chosen - subjects).group_by(&:status)
          .transform_values { |group| group.map { |s| s.feature.ordinal.to_s } }
      end

      # Pull requests that name no unit the plan declares. Reported rather
      # than guessed at: a pull request whose title says "PR-4" against a plan
      # that stops at PR-3 is a discrepancy someone should look at, and
      # silently filing it under PR-3 buries exactly that.
      #
      # @return [Hash{String => Array<SpecPlanBuild::PullRequest>}] by ordinal
      def unattached
        @unattached ||= subjects.each_with_object({}) do |subject, found|
          claimed = units_for(subject).flat_map(&:pull_requests)
          loose = subject.pull_requests - claimed
          found[subject.feature.ordinal.to_s] = loose unless loose.empty?
        end
      end

      private

      # @return [SpecPlanBuild::Tree]
      attr_reader :tree

      # @return [SpecPlanBuild::Ordinal, nil]
      attr_reader :since

      # @return [Array<Symbol>, nil]
      attr_reader :statuses

      # @return [Boolean]
      attr_reader :force

      # @return [Array<SpecPlanBuild::Subject>]
      def subjects = @subjects ||= chosen.select { |s| SpecPlanBuild::Linear.placement(s.status) }

      # @return [Array<SpecPlanBuild::Subject>] before the placement question
      def chosen
        @chosen ||= tree.subjects.select { |s|
          (since.nil? || s.feature.ordinal >= since) &&
            (statuses.nil? || statuses.include?(s.status.key))
        }
      end

      # @param subject [SpecPlanBuild::Subject]
      # @return [Array<SpecPlanBuild::Linear::Unit>]
      def units_for(subject) = (@units ||= {})[subject.feature.path] ||= Units.new(subject:).all

      # @param subject [SpecPlanBuild::Subject]
      # @return [SpecPlanBuild::Linear::Issues]
      def record_for(subject) = (@records ||= {})[subject.feature.path] ||= Issues.new(dir: subject.feature.path)

      # @param subject [SpecPlanBuild::Subject]
      # @return [Array<SpecPlanBuild::Linear::Action>]
      def actions_for(subject)
        [project_action(subject)] + units_for(subject).map { |unit| issue_action(subject, unit) }
      end

      # @param subject [SpecPlanBuild::Subject]
      # @return [SpecPlanBuild::Linear::Action]
      def project_action(subject)
        name = project_name(subject)
        recorded = record_for(subject).project
        args = {name:, description: project_description(subject), addTeams: [team]}
        digest = Issues.digest(args)

        op, reason = decide(recorded && recorded[:name], recorded && recorded[:digest], digest, "project")
        args = args.merge(id: recorded[:name]).except(:name, :addTeams) if op == :update && recorded

        Action.new(kind: :project, op:, ordinal: subject.feature.ordinal.to_s, unit: nil,
          identifier: recorded && recorded[:name], title: name, digest:, args:, reason:)
      end

      # @param subject [SpecPlanBuild::Subject]
      # @param unit [SpecPlanBuild::Linear::Unit]
      # @return [SpecPlanBuild::Linear::Action]
      def issue_action(subject, unit)
        placement = SpecPlanBuild::Linear.placement(subject.status)
        recorded = record_for(subject).by_unit[unit.key]
        title = issue_title(subject, unit)

        args = {team:, project: project_name(subject), title:,
                description: issue_description(subject, unit),
                state: placement.name, labels: placement.labels}
        digest = Issues.digest(args.merge(links: unit.pull_requests.map(&:url)))

        op, reason = decide(recorded&.identifier, recorded&.digest, digest, "issue")
        args = args.merge(links: links_for(unit)) if op == :create
        args = args.merge(id: recorded.identifier).except(:team, :project) if op == :update && recorded

        Action.new(kind: :issue, op:, ordinal: subject.feature.ordinal.to_s, unit: unit.key,
          identifier: recorded&.identifier, title:, digest:, args:, reason:)
      end

      # The three-way decision, in one place so a project and an issue cannot
      # answer it differently.
      #
      # @param existing [String, nil] what Linear already calls it
      # @param was [String, nil] the digest recorded at the last push
      # @param now [String] the digest of what we would push
      # @param noun [String]
      # @return [Array(Symbol, String)] the operation and its reason
      def decide(existing, was, now, noun)
        return [:create, "no #{noun} recorded in #{Issues::FILENAME}"] if existing.nil?
        return [:update, "--force"] if force
        return [:skip, "unchanged since the last import"] if was == now

        [:update, "the plan has changed since #{existing} was pushed"]
      end

      # @param subject [SpecPlanBuild::Subject]
      # @return [String]
      def project_name(subject) = "#{subject.feature.ordinal} #{heading(subject)}"

      # The specification's own H1 when it has one, because an agent writing
      # `spec.md` gives it a real sentence — "Tenancy: users, households,
      # memberships" — while the folder slug can only carry kebab-case.
      #
      # @param subject [SpecPlanBuild::Subject]
      # @return [String]
      def heading(subject)
        line = subject.read("spec.md").to_s[/^[ \t]{0,3}#[ \t]+(.+)$/, 1]
        cleaned = line.to_s.sub(/\A(?:spec(?:ification)?\s*)?\d+(?:\.\d+)?\s*[—–:.-]\s*/i, "").strip
        cleaned.empty? ? subject.feature.title : cleaned
      end

      # An undivided plan's one issue is the plan, so it takes the plan's own
      # words rather than the folder slug titleized back into "Yard
      # Documentation Gate".
      #
      # @param subject [SpecPlanBuild::Subject]
      # @param unit [SpecPlanBuild::Linear::Unit]
      # @return [String]
      def issue_title(subject, unit)
        words = unit.whole? ? heading(subject) : unit.label
        "[#{subject.feature.ordinal}] #{words}"
      end

      # @param subject [SpecPlanBuild::Subject]
      # @return [String]
      def project_description(subject)
        loose = unattached[subject.feature.ordinal.to_s].to_a

        [
          subject.goal.join("\n\n"),
          "**State**: #{subject.status} — #{subject.status.note}",
          "**Folder**: `#{SpecPlanBuild::PLANS_DIR}/#{subject.feature.dirname}`",
          loose.empty? ? nil : "**Pull requests naming no unit**\n\n#{bullets(loose)}",
          provenance
        ].compact.reject(&:empty?).join("\n\n")
      end

      # @param subject [SpecPlanBuild::Subject]
      # @param unit [SpecPlanBuild::Linear::Unit]
      # @return [String]
      def issue_description(subject, unit)
        [
          truncate(unit.body),
          unit.pull_requests.empty? ? nil : "**Pull requests**\n\n#{bullets(unit.pull_requests)}",
          "**Plan**: `#{SpecPlanBuild::PLANS_DIR}/#{subject.feature.dirname}`" \
            "#{" · unit `#{unit.key}`" unless unit.whole?}",
          provenance
        ].compact.reject(&:empty?).join("\n\n")
      end

      # Pull requests go into the description as markdown rather than only as
      # Linear attachments, because a description is rewritten wholesale on
      # every update while attachments are append-only — the same list sent
      # twice is idempotent in one and a growing pile in the other.
      #
      # @param prs [Array<SpecPlanBuild::PullRequest>]
      # @return [String]
      def bullets(prs)
        prs.map { |pr| "- #{pr.url ? "[#{pr.label}](#{pr.url})" : pr.label} — #{pr.state}" }.join("\n")
      end

      # @param unit [SpecPlanBuild::Linear::Unit]
      # @return [Array<Hash>]
      def links_for(unit)
        unit.pull_requests.select(&:url).map { |pr| {url: pr.url, title: pr.label} }
      end

      # A plan section can run to several hundred lines of design notes and
      # DDL. Linear is where the work is tracked, not where it is specified,
      # and the folder is one click away.
      #
      # @param body [String]
      # @param limit [Integer]
      # @return [String]
      def truncate(body, limit = 6_000)
        text = body.to_s.strip
        return text if text.length <= limit

        "#{text[0, limit].rpartition("\n").first.rstrip}\n\n_…truncated; the plan folder has the rest._"
      end

      # @return [String]
      def provenance
        "_Imported by `spec-plan-build linear import`. The plan folder is the source of truth; " \
          "edits made here do not travel back._"
      end
    end
  end
end
