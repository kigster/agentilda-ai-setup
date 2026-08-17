# frozen_string_literal: true

# Backs `/spec-create <name of the spec>`.
RSpec.describe SpecPlanBuild::Creator, :tree do
  subject(:creator) { described_class.new(dir: plans_root) }

  let(:created) { File.basename(creator.create(words:).value!) }
  let(:words) { %w[tax rule dsl] }

  describe "#create" do
    context "with an empty tree" do
      it "starts at 000.00 and opens in the spec phase" do
        expect(created).to eq("000.00-⚪️-tax-rule-dsl")
      end
    end

    context "with plans already present" do
      let!(:tree) do
        plans do |t|
          t.plan "001.00", :new, "initial-spec", files: {"spec.md" => spec_body}
          t.plan "002.00", :done, "dev-foundation", prs: [t.merged(2, "Ship it")]
        end
      end

      it "takes the next whole number, padded to .00" do
        expect(created).to eq("003.00-⚪️-tax-rule-dsl")
      end

      it "creates the directory on disk" do
        expect(File.directory?(creator.create(words:).value!)).to be(true)
      end

      it "ignores retroactive siblings when choosing the next number" do
        plans { |t| t.plan "002.01", :done, "backfill", prs: [t.merged(9, "x")] }

        expect(created).to eq("003.00-⚪️-tax-rule-dsl")
      end
    end

    describe "slugification" do
      it "lowercases, joins on hyphens and drops punctuation" do
        aggregate_failures do
          expect(described_class.slugify(["Tax Rule DSL"])).to eq("tax-rule-dsl")
          expect(described_class.slugify(%w[Multi-Tenant Billing!])).to eq("multi-tenant-billing")
          expect(described_class.slugify(["  spaced   out  "])).to eq("spaced-out")
        end
      end

      it "refuses a topic that slugifies to nothing, rather than making a folder called '-'" do
        expect(creator.create(words: ["!!!"])).to be_failure
      end
    end

    context "when the same topic is created twice" do
      let!(:tree) { plans { |t| t.plan "001.00", :new, "tax-rule-dsl", files: {"spec.md" => spec_body} } }

      it "gives the second one its own number rather than colliding" do
        expect(created).to eq("002.00-⚪️-tax-rule-dsl")
      end

      it "never overwrites the folder that is already there" do
        creator.create(words:)

        expect(File.exist?(File.join(plans_root, "001.00-⚪️-tax-rule-dsl", "spec.md"))).to be(true)
      end
    end
  end

  describe "#create with :after — a plan written after the fact" do
    let!(:tree) do
      plans do |t|
        t.plan "001.00", :new, "initial-spec", files: {"spec.md" => spec_body}
        t.plan "002.00", :done, "dev-foundation", prs: [t.merged(2, "Ship it")]
        t.plan "003.00", :new, "tenancy", files: {"spec.md" => spec_body}
      end
    end

    let(:retro) { File.basename(creator.create(words: %w[schedule k1 backfill], after: "002").value!) }

    it "takes a decimal slot in the gap, so the number itself records the retroactivity" do
      expect(retro).to eq("002.01-⬜️-schedule-k1-backfill")
    end

    it "takes the next free slot when the gap is already partly used" do
      plans { |t| t.plan "002.01", :retroactive, "earlier-backfill", prs: [t.merged(8, "x")] }

      expect(retro).to eq("002.02-⬜️-schedule-k1-backfill")
    end

    it "accepts the anchor in either shape" do
      expect(File.basename(creator.create(words: %w[a b], after: "002.00").value!))
        .to start_with("002.01-")
    end

    it "refuses to anchor against a plan that does not exist" do
      expect(creator.create(words: %w[a b], after: "099")).to be_failure
    end

    it "births retroactive plans as ⬜️, since the work exists but the documents do not" do
      expect(retro).to include("⬜️")
    end
  end

  describe "an explicit status" do
    it "honours one when given, rather than always opening at ⚪️" do
      expect(File.basename(creator.create(words:, status: "ready").value!))
        .to eq("000.00-⭐️-tax-rule-dsl")
    end

    it "rejects a status it does not recognise" do
      expect(creator.create(words:, status: "chartreuse")).to be_failure
    end
  end
end
