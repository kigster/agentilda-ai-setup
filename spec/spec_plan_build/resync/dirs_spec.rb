# frozen_string_literal: true

# Backs `/spec-plan-build resync dirs` — reconciles every folder's emoji with
# what the folder actually contains.
RSpec.describe SpecPlanBuild::Resync::Dirs, :tree do
  subject(:resync) { described_class.new(tree: SpecPlanBuild::Tree.new(dir: plans_root)) }

  let(:changes) { resync.plan }
  let(:names) { Dir.children(plans_root).sort }

  describe "#plan" do
    context "when every folder's name is already honest" do
      let!(:tree) do
        plans do |t|
          t.plan "001.00", :new, "initial-spec", files: {"spec.md" => spec_body}
          t.plan "002.00", :ready, "dev-foundation", files: {"spec.md" => spec_body, "plan.md" => "# Plan"}
          t.plan "003.00", :done, "ledger", prs: [t.merged(3, "Ship it")]
        end
      end

      it "proposes nothing" do
        expect(changes).to be_empty
      end
    end

    context "when a folder has outgrown its emoji" do
      let!(:tree) do
        plans do |t|
          t.plan "001.00", :new, "initial-spec", files: {"spec.md" => spec_body, "plan.md" => "# Plan"}
        end
      end

      it "proposes the state the contents justify" do
        expect(changes.map { |c| [c.from, c.to] }).to eq([[:new, :ready]])
      end

      it "keeps the number and the slug, changing only the emoji" do
        expect(File.basename(changes.first.target)).to eq("001.00-⭐️-initial-spec")
      end
    end

    context "when a folder claims Done with an open pull request" do
      let!(:tree) do
        plans do |t|
          t.plan "004.00", :done, "deploy", prs: [t.merged(1, "a"), t.open(2, "b")]
        end
      end

      it "walks it back to In Progress" do
        expect(changes.map(&:to)).to eq([:wip])
      end

      it "records why, so the rename is auditable rather than mysterious" do
        expect(changes.first.reason).to match(/1 pull request still open/)
      end
    end

    # ⭕️ and 🅱️ share an invariant deliberately; only the folder name says
    # which human must decide, and resync must not overwrite that.
    it "never reclassifies between the two blocked states" do
      plans do |t|
        t.plan "005.00", :blocked, "engine-choice", files: {"blocked.md" => "B1"}
        t.plan "006.00", :product_blocked, "pricing", files: {"blocked.md" => "B1"}
      end

      expect(changes).to be_empty
    end

    it "leaves folders it cannot classify alone rather than guessing" do
      plans { |t| t.plan "007.00", :new, "empty-shell" }

      expect(changes).to be_empty
    end

    it "skips directories that carry no plan number" do
      plans { |t| t.stray("notes") }

      expect(changes).to be_empty
    end
  end

  describe "#call" do
    let!(:tree) do
      plans do |t|
        t.plan "001.00", :new, "initial-spec", files: {"spec.md" => spec_body, "plan.md" => "# Plan"}
      end
    end

    it "changes nothing without an explicit commit" do
      resync.call

      expect(names).to eq(["001.00-⚪️-initial-spec"])
    end

    it "renames the folder when committed" do
      resync.call(commit: true)

      expect(names).to eq(["001.00-⭐️-initial-spec"])
    end

    it "preserves the folder's contents across the rename" do
      resync.call(commit: true)

      expect(File.exist?(File.join(plans_root, "001.00-⭐️-initial-spec", "plan.md"))).to be(true)
    end

    it "reports what it did" do
      expect(resync.call(commit: true).map(&:to)).to eq([:ready])
    end

    it "is idempotent — a second run finds nothing left to do" do
      resync.call(commit: true)

      expect(described_class.new(tree: SpecPlanBuild::Tree.new(dir: plans_root)).plan).to be_empty
    end
  end
end
