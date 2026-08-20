# frozen_string_literal: true

module SpecPlanBuild
  module Linear
    # What one {Action} actually did.
    #
    # @!attribute [r] action
    #   @return [SpecPlanBuild::Linear::Action]
    # @!attribute [r] identifier
    #   @return [String, nil] "TAX-41", or a project name
    # @!attribute [r] url
    #   @return [String, nil]
    # @!attribute [r] error
    #   @return [String, nil] why it did not happen
    Result = Data.define(:action, :identifier, :url, :error) do
      # @return [Boolean]
      def ok? = error.nil?
    end

    # Applies an {Import} through the {API}, then writes each plan's
    # `linear.md` so the next run knows what this one did.
    #
    # Plans are pushed one at a time and in order. There is no concurrency
    # here on purpose: within a plan the project must exist before its issues
    # can join it, and across plans the gain would be a few seconds against
    # the risk of two threads racing to create the same label on a team that
    # does not have it yet.
    class Push
      # @param import [SpecPlanBuild::Linear::Import]
      # @param api [SpecPlanBuild::Linear::API]
      # @param tree [SpecPlanBuild::Tree]
      def initialize(import:, api:, tree:)
        @import = import
        @api = api
        @tree = tree
      end

      # @return [Array<SpecPlanBuild::Linear::Result>] every action attempted,
      #   skips included, in plan order
      def call
        by_plan.flat_map { |ordinal, actions| push_plan(ordinal, actions) }
      end

      private

      # @return [SpecPlanBuild::Linear::Import]
      attr_reader :import

      # @return [SpecPlanBuild::Linear::API]
      attr_reader :api

      # @return [SpecPlanBuild::Tree]
      attr_reader :tree

      # @return [Hash] the team, its states and its labels
      def team = @team ||= api.team(import.team)

      # @return [Hash{String => Array<SpecPlanBuild::Linear::Action>}]
      def by_plan = import.actions.group_by(&:ordinal)

      # @param ordinal [String]
      # @param actions [Array<SpecPlanBuild::Linear::Action>]
      # @return [Array<SpecPlanBuild::Linear::Result>]
      def push_plan(ordinal, actions)
        subject = tree.find(ordinal) or return []
        projects, issue_actions = actions.partition { |a| a.kind == :project }
        return [] if projects.empty?

        project = apply_project(projects.first, subject)
        results = [project] + issue_actions.map { |action| apply_issue(action, project, subject) }
        record(subject, project, results)
        results
      end

      # @param action [SpecPlanBuild::Linear::Action]
      # @param subject [SpecPlanBuild::Subject]
      # @return [SpecPlanBuild::Linear::Result]
      def apply_project(action, subject)
        attempt(action) do
          recorded = Issues.new(dir: subject.feature.path).project || {name: action.title, url: nil}

          node = case action.op
          when :skip then existing_project(recorded[:name]) || {"name" => recorded[:name], "url" => recorded[:url]}
          when :update then update_project(action, recorded)
          else api.create_project(name: action.args[:name], teamIds: [team[:id]],
            content: action.args[:description])
          end

          [node["name"] || action.title, node["url"]]
        end
      end

      # @param action [SpecPlanBuild::Linear::Action]
      # @param recorded [Hash]
      # @return [Hash]
      def update_project(action, recorded)
        found = existing_project(recorded[:name])
        unless found
          return api.create_project(name: action.title, teamIds: [team[:id]],
            content: action.args[:description])
        end

        api.update_project(found["id"], content: action.args[:description])
      end

      # @param name [String]
      # @return [Hash, nil]
      def existing_project(name)
        @projects ||= api.projects(team[:id])
        @projects.find { |p| p["name"].to_s.casecmp?(name.to_s) }
      end

      # @param action [SpecPlanBuild::Linear::Action]
      # @param project [SpecPlanBuild::Linear::Result]
      # @param subject [SpecPlanBuild::Subject]
      # @return [SpecPlanBuild::Linear::Result]
      def apply_issue(action, project, subject)
        unless project.ok?
          return Result.new(action:, identifier: action.identifier, url: nil,
            error: "its project could not be created")
        end

        attempt(action) do
          node = case action.op
          when :skip then skipped_issue(action, subject)
          when :update then api.update_issue(action.args[:id], issue_input(action))
          else create_issue(action)
          end

          [node["identifier"], node["url"]]
        end
      end

      # @param action [SpecPlanBuild::Linear::Action]
      # @return [Hash]
      def create_issue(action)
        node = api.create_issue(issue_input(action).merge(teamId: team[:id], projectId: project_id(action)))
        Array(action.args[:links]).each { |l| api.link(issue_id: node["id"], url: l[:url], title: l[:title]) }
        node
      end

      # @param action [SpecPlanBuild::Linear::Action]
      # @param subject [SpecPlanBuild::Subject]
      # @return [Hash]
      def skipped_issue(action, subject)
        was = Issues.new(dir: subject.feature.path).by_unit[action.unit]
        {"identifier" => was&.identifier || action.identifier, "url" => was&.url}
      end

      # @param action [SpecPlanBuild::Linear::Action]
      # @return [Hash]
      def issue_input(action)
        {title: action.args[:title], description: action.args[:description],
         stateId: state_id(action.args[:state]), labelIds: label_ids(action.args[:labels])}.compact
      end

      # @param action [SpecPlanBuild::Linear::Action]
      # @return [String, nil]
      def project_id(action) = existing_project(action.args[:project])&.fetch("id")

      # A team names its own workflow states, so the name we would prefer is a
      # preference and the type is the contract. Falling back to the type is
      # what lets this run against a workspace whose "In Progress" is called
      # something else entirely.
      #
      # @param name [String]
      # @return [String, nil]
      def state_id(name)
        placement = PLACEMENTS.values.find { |p| p.name == name }
        states = team[:states]

        found = states.find { |s| s["name"].to_s.casecmp?(name.to_s) }
        found ||= states.select { |s| s["type"] == placement&.type }.min_by { |s| s["position"].to_f }
        found && found["id"]
      end

      # @param names [Array<String>]
      # @return [Array<String>]
      def label_ids(names)
        Array(names).map do |name|
          found = team[:labels].find { |l| l["name"].to_s.casecmp?(name) }
          found ||= api.create_label(name, team[:id]).tap { |made| team[:labels] << made }
          found["id"]
        end
      end

      # Every Linear call is wrapped, so one plan that fails — a state the
      # team does not have, a project name already taken by something else —
      # does not abandon the twenty plans queued behind it.
      #
      # @param action [SpecPlanBuild::Linear::Action]
      # @yieldreturn [Array(String, String)] identifier and url
      # @return [SpecPlanBuild::Linear::Result]
      def attempt(action)
        identifier, url = yield
        Result.new(action:, identifier:, url:, error: nil)
      rescue Error => e
        Result.new(action:, identifier: action.identifier, url: nil, error: e.message)
      end

      # `linear.md` is rewritten from what actually happened, including the
      # skips — a row dropped because its action was a no-op is a row the next
      # run would recreate from scratch.
      #
      # @param subject [SpecPlanBuild::Subject]
      # @param project [SpecPlanBuild::Linear::Result]
      # @param results [Array<SpecPlanBuild::Linear::Result>]
      # @return [void]
      def record(subject, project, results)
        issues = results.select { |r| r.action.kind == :issue && r.ok? && r.identifier }
          .map { |r|
            Issue.new(unit: r.action.unit, identifier: r.identifier, url: r.url,
              title: r.action.title, state: r.action.args[:state] || "", digest: r.action.digest)
          }
        return if issues.empty? && !project.ok?

        Issues.new(dir: subject.feature.path).write(team: import.team, issues:,
          project: project.ok? ? {name: project.identifier, url: project.url, digest: project.action.digest} : nil)
      end
    end
  end
end
