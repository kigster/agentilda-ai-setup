# frozen_string_literal: true

# The push is the only part that talks to Linear, so it is the only part that
# needs a fake. The transport is injected at the GraphQL boundary rather than
# stubbed on the API object, so the queries themselves are exercised: a
# mutation whose variables are wrong still fails here.
RSpec.describe SpecPlanBuild::Linear::Push, :tree do
  subject(:push) { described_class.new(import:, api:, tree:) }

  let(:tree) { SpecPlanBuild::Tree.new(dir: plans_root) }
  let(:import) { SpecPlanBuild::Linear::Import.new(tree: SpecPlanBuild::Tree.new(dir: plans_root), team: "TAX") }
  let(:api) { SpecPlanBuild::Linear::API.new(transport: fake) }
  let(:calls) { [] }

  let(:states) do
    [{"id" => "s-backlog", "name" => "Backlog", "type" => "backlog", "position" => 0},
      {"id" => "s-todo", "name" => "Todo", "type" => "unstarted", "position" => 1},
      {"id" => "s-doing", "name" => "Doing", "type" => "started", "position" => 2},
      {"id" => "s-done", "name" => "Done", "type" => "completed", "position" => 3}]
  end

  let(:labels) { [{"id" => "l-blocked", "name" => "blocked"}] }

  # Answers whichever operation it is handed, and records what it was asked.
  let(:fake) do
    lambda { |document, variables|
      calls << [document[/mutation (\w+)|query (\w+)/, 1] || document[/query (\w+)/, 1], variables]
      {"data" => response_for(document, variables)}
    }
  end

  let!(:built) do
    plans do |t|
      t.plan "002.00", :approved, "dev-foundation",
        files: {"spec.md" => spec_body(title: "Dev Foundation"),
                "plan.md" => "## PR-1 — Test rig\n\nThe rig.\n"},
        prs: [t.merged(2, "Spec 002 PR-1: Test rig")]
    end
  end

  def response_for(document, variables)
    case document
    when /teams\(filter/
      {"teams" => {"nodes" => [{"id" => "team-1", "name" => "Tax", "key" => "TAX",
                                "states" => {"nodes" => states}, "labels" => {"nodes" => labels}}]}}
    when /projects\(first/ then {"team" => {"projects" => {"nodes" => @projects.to_a}}}
    when /projectCreate/
      made = {"id" => "p-1", "name" => variables[:input][:name], "url" => "https://linear.app/p-1"}
      (@projects ||= []) << made
      {"projectCreate" => {"success" => true, "project" => made}}
    when /projectUpdate/ then {"projectUpdate" => {"success" => true, "project" => @projects.first}}
    when /issueCreate/
      {"issueCreate" => {"success" => true,
                         "issue" => {"id" => "i-1", "identifier" => "TAX-41", "url" => "https://linear.app/TAX-41"}}}
    when /issueUpdate/
      {"issueUpdate" => {"success" => true,
                         "issue" => {"id" => "i-1", "identifier" => "TAX-41", "url" => "https://linear.app/TAX-41"}}}
    when /issueLabelCreate/
      {"issueLabelCreate" => {"success" => true, "issueLabel" => {"id" => "l-new", "name" => variables[:input][:name]}}}
    when /attachmentCreate/ then {"attachmentCreate" => {"success" => true, "attachment" => {"id" => "a-1"}}}
    end
  end

  describe "#call" do
    it "creates the project before the issues that have to join it" do
      push.call
      order = calls.map(&:first).compact

      expect(order.index("CreateProject")).to be < order.index("CreateIssue")
    end

    it "files the issue under the project it just made" do
      push.call
      _, variables = calls.find { |name, _| name == "CreateIssue" }

      expect(variables[:input]).to include(teamId: "team-1", projectId: "p-1")
    end

    it "attaches the pull request to the issue it created" do
      push.call
      _, variables = calls.find { |name, _| name == "CreateAttachment" }

      expect(variables[:input][:url]).to eq("https://github.com/example/repo/pull/2")
    end
  end

  describe "resolving a workflow state" do
    # A team that calls its started state "Doing" is not a broken team, and an
    # import that only knows the word "In Progress" would file every plan
    # wrong on it.
    it "falls back to the type when the team has no state by that name" do
      plans { |t| t.plan "005.00", :building, "in-flight", files: {"spec.md" => spec_body, "plan.md" => "x"}, prs: [t.open(9, "WIP")] }
      push.call
      created = calls.filter_map { |name, v| v[:input][:stateId] if name == "CreateIssue" }

      expect(created).to include("s-doing")
    end

    it "prefers the team's own name for a state when it has one" do
      push.call
      _, variables = calls.find { |name, _| name == "CreateIssue" }

      expect(variables[:input][:stateId]).to eq("s-done")
    end
  end

  describe "labels" do
    it "reuses a label the team already has rather than making a second one" do
      plans { |t| t.plan "006.00", :blocked, "stuck", files: {"blocked.md" => "B1. Which tier?"} }
      push.call

      aggregate_failures do
        expect(calls.map(&:first)).not_to include("CreateLabel")
        expect(calls.filter_map { |n, v| v[:input][:labelIds] if n == "CreateIssue" }).to include(["l-blocked"])
      end
    end

    it "creates one the team is missing" do
      plans { |t| t.plan "007.00", :deployed, "shipped", files: {"deployed.md" => "v1.2.0"} }
      push.call

      expect(calls.filter_map { |n, v| v[:input][:name] if n == "CreateLabel" }).to eq(["deployed"])
    end
  end

  describe "what it records" do
    let(:written) { File.read(File.join(plans_root, "002.00-✅-dev-foundation", "linear.md")) }

    before { push.call }

    it "writes a linear.md naming the issue Linear gave back" do
      expect(written).to include("TAX-41", "https://linear.app/TAX-41")
    end

    it "records the project, so the next run does not make a second one" do
      expect(SpecPlanBuild::Linear::Issues.new(dir: File.join(plans_root, "002.00-✅-dev-foundation")).project)
        .to include(name: "002.00 Dev Foundation", url: "https://linear.app/p-1")
    end

    # The whole point of the fingerprint: an unchanged plan costs nothing.
    it "leaves a record a second import reads as nothing to do" do
      second = SpecPlanBuild::Linear::Import.new(tree: SpecPlanBuild::Tree.new(dir: plans_root), team: "TAX")

      expect(second.pending).to be_empty
    end
  end

  # The steady state. Everything above is the first run; this is every run
  # after it, and the failure it guards against — a second project, a second
  # issue, a duplicate of the lot — is the one that would be worst to find
  # out about by looking at Linear.
  describe "running a second time over a tree it has already imported" do
    before { push.call }

    it "creates nothing at all" do
      calls.clear
      described_class.new(import: fresh_import, api:, tree:).call

      expect(calls.map(&:first)).not_to include("CreateProject", "CreateIssue")
    end

    it "keeps the record pointing at the same issue" do
      described_class.new(import: fresh_import, api:, tree:).call
      record = SpecPlanBuild::Linear::Issues.new(dir: File.join(plans_root, "002.00-✅-dev-foundation"))

      expect(record.all.map(&:identifier)).to eq(["TAX-41"])
    end

    it "updates rather than duplicates once the plan changes underneath it" do
      File.write(File.join(plans_root, "002.00-✅-dev-foundation", "plan.md"),
        "## PR-1 — Test rig, rewritten\n\nDifferent now.\n")
      calls.clear
      described_class.new(import: fresh_import, api:, tree:).call

      aggregate_failures do
        expect(calls.map(&:first)).to include("UpdateIssue")
        expect(calls.map(&:first)).not_to include("CreateIssue")
      end
    end

    # @return [SpecPlanBuild::Linear::Import] reading the tree as it now is
    def fresh_import
      SpecPlanBuild::Linear::Import.new(tree: SpecPlanBuild::Tree.new(dir: plans_root), team: "TAX")
    end
  end

  describe "when Linear refuses something" do
    let(:fake) do
      lambda { |document, variables|
        calls << [document[/mutation (\w+)|query (\w+)/, 1], variables]
        next {"errors" => [{"message" => "title is too long"}]} if document.match?(/issueCreate/)

        {"data" => response_for(document, variables)}
      }
    end

    it "reports the failure against the action that caused it" do
      failed = push.call.reject(&:ok?)

      expect(failed.map(&:error)).to all(include("title is too long"))
    end

    # Twenty plans queued behind one bad title is not a reason to abandon them.
    it "keeps going, so one bad plan does not strand the rest" do
      plans { |t| t.plan "008.00", :new, "next-one", files: {"spec.md" => spec_body} }

      expect(push.call.map(&:action).map(&:ordinal).uniq).to include("002.00", "008.00")
    end

    # The project really was created even though its issues were not, and a
    # run that forgot that would make a second project next time. So the
    # record is written — claiming the project, and claiming no issue.
    it "records the project it did make, and no issue it did not" do
      push.call
      record = SpecPlanBuild::Linear::Issues.new(dir: File.join(plans_root, "002.00-✅-dev-foundation"))

      aggregate_failures do
        expect(record.project).to include(name: "002.00 Dev Foundation")
        expect(record.all).to be_empty
      end
    end

    it "leaves the failed issue to be retried by the next run" do
      push.call
      second = SpecPlanBuild::Linear::Import.new(tree: SpecPlanBuild::Tree.new(dir: plans_root), team: "TAX")

      expect(second.pending.select { |a| a.kind == :issue }.map(&:op)).to include(:create)
    end
  end
end
