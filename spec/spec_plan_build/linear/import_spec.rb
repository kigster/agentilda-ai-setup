# frozen_string_literal: true

# The import decides everything from disk. That is the property worth
# protecting: `--commit` is only honest because the dry run and the push
# consume the same object, so what gets printed and what gets sent cannot
# disagree.
RSpec.describe SpecPlanBuild::Linear::Import, :tree do
  subject(:import) { described_class.new(tree: SpecPlanBuild::Tree.new(dir: plans_root), team: "TAX", **options) }

  let(:options) { {} }

  let!(:tree) do
    plans do |t|
      t.plan "001.00", :new, "initial-spec",
        files: {"spec.md" => spec_body(title: "Answer one question", goal: "Make it work.")}
      t.plan "002.00", :approved, "dev-foundation",
        files: {"spec.md" => spec_body(title: "Dev Foundation"),
                "plan.md" => "## PR-1 — Test rig\n\nThe rig.\n\n## PR-2 — Rails foundation\n\nThe app.\n"},
        prs: [t.merged(2, "Spec 002 PR-1: Test rig"), t.merged(3, "Spec 002 PR-2: Rails foundation")]
      t.plan "003.00", :blocked, "pricing", files: {"blocked.md" => "B1. Which tier?"}
    end
  end

  describe "what it proposes" do
    it "gives every plan a project and every work unit an issue" do
      expect(import.actions.map { |a| [a.ordinal, a.kind, a.unit] }).to eq(
        [["001.00", :project, nil], ["001.00", :issue, "PLAN"],
          ["002.00", :project, nil], ["002.00", :issue, "PR-1"], ["002.00", :issue, "PR-2"],
          ["003.00", :project, nil], ["003.00", :issue, "PLAN"]]
      )
    end

    it "numbers every issue title with the plan it came from, as pull requests are" do
      titles = import.actions.select { |a| a.kind == :issue }.map(&:title)

      expect(titles).to all(match(/\A\[\d{3}\.\d{2}\] /))
    end

    it "names the project from the specification's own heading, not the folder slug" do
      project = import.actions.find { |a| a.kind == :project && a.ordinal == "001.00" }

      expect(project.title).to eq("001.00 Answer one question")
    end
  end

  describe "the arguments it emits" do
    let(:issue) { import.actions.find { |a| a.kind == :issue && a.unit == "PR-1" } }

    # They are the Linear MCP server's own argument names on purpose: the same
    # JSON has to drive both transports, or the two will drift.
    it "addresses everything by the names a human already knows" do
      expect(issue.args).to include(team: "TAX", project: a_string_starting_with("002.00"),
        state: "Done", labels: [])
    end

    it "carries the state a folder in this state belongs in" do
      blocked = import.actions.find { |a| a.kind == :issue && a.ordinal == "003.00" }

      expect(blocked.args).to include(state: "Todo", labels: %w[blocked])
    end

    # Descriptions are rewritten wholesale on every update; Linear attachments
    # are append-only. The same list sent twice is idempotent in one and a
    # growing pile in the other.
    it "puts the pull requests in the description, where a re-send is harmless" do
      expect(issue.args[:description]).to include("/pull/2", "Merged 🟣")
    end

    it "attaches them as links too, but only when the issue is being created" do
      expect(issue.args[:links]).to eq([{url: "https://github.com/example/repo/pull/2",
                                         title: "#2 — Spec 002 PR-1: Test rig"}])
    end

    it "points back at the folder, so a reader can find the source of truth" do
      expect(issue.args[:description]).to include("`.plans/002.00-✅-dev-foundation`")
    end
  end

  describe "deciding between create, update and skip" do
    # The digest this import would compute for PR-1 as the plan stands, read
    # from an instance of its own so memoization cannot serve a stale answer.
    #
    # @return [String]
    def unchanged_digest
      described_class.new(tree: SpecPlanBuild::Tree.new(dir: plans_root), team: "TAX")
        .actions.find { |a| a.unit == "PR-1" }.digest
    end

    def record(ordinal, dirname, digest:, unit: "PR-1", identifier: "TAX-41")
      File.write(File.join(plans_root, dirname, "linear.md"),
        SpecPlanBuild::Linear::Issues.render(team: "TAX",
          project: {name: "#{ordinal} Dev Foundation", url: "https://linear.app/p", digest: "0" * 8},
          issues: [SpecPlanBuild::Linear::Issue.new(unit:, identifier:, url: "https://linear.app/i",
            title: "t", state: "Done", digest:)]))
    end

    it "creates what no linear.md has ever heard of" do
      expect(import.actions).to all(have_attributes(op: :create))
    end

    it "skips an issue whose fingerprint still matches the plan" do
      record("002.00", "002.00-✅-dev-foundation", digest: unchanged_digest)

      expect(import.actions.find { |a| a.unit == "PR-1" }).to have_attributes(op: :skip, identifier: "TAX-41")
    end

    it "updates an issue whose plan has changed underneath it" do
      record("002.00", "002.00-✅-dev-foundation", digest: "deadbeef")
      action = import.actions.find { |a| a.unit == "PR-1" }

      aggregate_failures do
        expect(action.op).to eq(:update)
        expect(action.reason).to match(/changed since TAX-41 was pushed/)
        expect(action.args).to include(id: "TAX-41")
      end
    end

    it "addresses an update by identifier and stops re-stating the team" do
      record("002.00", "002.00-✅-dev-foundation", digest: "deadbeef")
      action = import.actions.find { |a| a.unit == "PR-1" }

      expect(action.args.keys).not_to include(:team, :project, :links)
    end

    context "with --force" do
      let(:options) { {force: true} }

      it "updates even what it would otherwise have left alone" do
        record("002.00", "002.00-✅-dev-foundation", digest: unchanged_digest)

        expect(import.actions.find { |a| a.unit == "PR-1" }).to have_attributes(op: :update, reason: "--force")
      end
    end
  end

  describe "choosing which plans to import" do
    it "skips everything numbered below --since" do
      filtered = described_class.new(tree: SpecPlanBuild::Tree.new(dir: plans_root), team: "TAX", since: "002.00")

      expect(filtered.actions.map(&:ordinal).uniq).to eq(%w[002.00 003.00])
    end

    it "keeps only the states asked for" do
      filtered = described_class.new(tree: SpecPlanBuild::Tree.new(dir: plans_root), team: "TAX",
        statuses: [:blocked])

      expect(filtered.actions.map(&:ordinal).uniq).to eq(%w[003.00])
    end
  end

  describe "a plan whose state nobody has decided how to file" do
    before do
      plans do |t|
        t.plan "009.00", :shit, "scrapped-work", files: {"rewrite.md" => "Start again."}
        t.plan "010.00", :rolled_back, "pulled", files: {"rollback.md" => "It broke checkout."}
      end
    end

    it "proposes nothing for it" do
      expect(import.actions.map(&:ordinal)).not_to include("009.00", "010.00")
    end

    # Skipping quietly and filing it somewhere plausible are the same failure
    # wearing different clothes: nobody finds out.
    it "reports it, grouped by the state that stopped it" do
      expect(import.unplaced.transform_keys(&:key))
        .to eq(shit: ["009.00"], rolled_back: ["010.00"])
    end

    it "still imports every plan whose state it does know" do
      expect(import.actions.map(&:ordinal)).to include("001.00", "002.00", "003.00")
    end
  end

  describe "#unattached" do
    # Filing it under the nearest unit would bury exactly the discrepancy
    # somebody needs to see.
    it "reports a pull request that names a unit the plan does not declare" do
      plans do |t|
        t.plan "004.00", :building, "engine",
          files: {"spec.md" => spec_body, "plan.md" => "## PR-1 — One\n\n## PR-2 — Two\n"},
          prs: [t.merged(5, "Spec 004 PR-1: One"), t.merged(6, "Spec 004 PR-9: Nine")]
      end

      expect(import.unattached["004.00"].map(&:number)).to eq(["6"])
    end

    it "says nothing about a plan whose pull requests all found a home" do
      expect(import.unattached).not_to have_key("002.00")
    end
  end

  describe "#to_json" do
    it "emits the team and every action, ready for the MCP transport" do
      parsed = JSON.parse(import.to_json)

      aggregate_failures do
        expect(parsed["team"]).to eq("TAX")
        expect(parsed["actions"].size).to eq(import.actions.size)
        expect(parsed["actions"].first["args"]).to have_key("name")
      end
    end
  end
end
