# frozen_string_literal: true

# Backs `/spec-status` — the table of every feature, its status in words and
# icon, and its pull requests as clickable links.
RSpec.describe SpecPlanBuild::Reporter, :tree do
  subject(:reporter) { described_class.new(tree: SpecPlanBuild::Tree.new(dir: plans_root)) }

  let!(:tree) do
    plans do |t|
      t.plan "001.00", :new, "initial-spec", files: {"spec.md" => spec_body(title: "Initial Spec")}
      t.plan "002.00", :done, "dev-foundation",
        files: {"spec.md" => spec_body},
        prs: [t.merged(2, "Frontend test rig"), t.merged(3, "Rails foundation")]
      t.plan "018.01", :wip, "verify-returns", prs: [t.open(92, "Send mail through Resend")]
      t.plan "003.00", :blocked, "pricing", files: {"blocked.md" => "B1. Which tier?"}
    end
  end

  let(:table) { reporter.render }

  describe "#render" do
    it "lists every plan in number order, retroactive siblings in their gap" do
      expect(table.scan(/\b\d{3}\.\d{2}\b/)).to eq(%w[001.00 002.00 003.00 018.01])
    end

    it "shows each status as both icon and words" do
      aggregate_failures do
        expect(table).to include("⚪️").and include("New")
        expect(table).to include("✅").and include("Done")
        expect(table).to include("🟡").and include("In Progress")
        expect(table).to include("⭕️").and include("Blocked")
      end
    end

    it "renders the feature name from the slug" do
      expect(table).to include("Dev Foundation")
    end

    it "makes pull requests clickable" do
      expect(table).to include("https://github.com/example/repo/pull/92")
    end

    it "shows every pull request a plan records, not just the first" do
      aggregate_failures do
        expect(table).to include("/pull/2")
        expect(table).to include("/pull/3")
      end
    end

    it "says so plainly when a plan has no pull requests yet" do
      expect(table).to match(/001\.00.*(—|none|no PRs)/i)
    end
  end

  describe "counts" do
    it "totals plans by status" do
      expect(reporter.totals).to include(done: 1, new: 1, wip: 1, blocked: 1)
    end
  end

  describe "consistency" do
    let!(:tree) do
      plans { |t| t.plan "001.00", :done, "lying", prs: [t.open(5, "still open")] }
    end

    it "flags a plan whose status its contents do not justify" do
      expect(reporter.inconsistent.map { |s| s.feature.ordinal.to_s }).to eq(["001.00"])
    end

    it "explains what is wrong, not merely that something is" do
      expect(reporter.inconsistent.first.violation).to match(/1 pull request still open/)
    end
  end

  describe "an empty tree" do
    let!(:tree) { plans }

    it "says the tree is empty rather than printing a headerless table" do
      expect(table).to match(/no plans/i)
    end
  end

  describe "table discipline" do
    it "writes nothing to STDERR, so the table composes in a pipe" do
      expect { reporter.render }.not_to output.to_stderr
    end
  end
end
