# frozen_string_literal: true

# Linear has five workflow state types and every workspace renames them, so a
# placement carries both the type it means and the name it would prefer.
RSpec.describe SpecPlanBuild::Linear do
  describe "PLACEMENTS" do
    # The failure this guards is silent: a sixteenth state gets added to
    # STATUSES, nothing here changes, and its plans import as whatever the
    # fallback happens to be with no indication anything was missed.
    it "places every state the folder names can carry" do
      expect(described_class::PLACEMENTS.keys).to match_array(SpecPlanBuild::STATUSES.map(&:key))
    end

    it "uses only the five types Linear actually has" do
      types = described_class::PLACEMENTS.values.map(&:type).uniq

      expect(types - described_class::TYPES).to be_empty
    end

    it "labels the states whose meaning the type cannot carry" do
      aggregate_failures do
        expect(described_class::PLACEMENTS[:blocked].labels).to eq(%w[blocked])
        expect(described_class::PLACEMENTS[:product_blocked].labels).to eq(%w[blocked-on-product])
        expect(described_class::PLACEMENTS[:deployed].labels).to eq(%w[deployed])
      end
    end

    # ⭕️ and 🅱️ are the same position on a board and different reasons.
    it "distinguishes the two blocks by label, since both sit in the same column" do
      technical = described_class::PLACEMENTS[:blocked]
      product = described_class::PLACEMENTS[:product_blocked]

      aggregate_failures do
        expect(technical.type).to eq(product.type)
        expect(technical.labels).not_to eq(product.labels)
      end
    end
  end

  describe ".placement" do
    it "answers with where a state belongs" do
      placement = described_class.placement(SpecPlanBuild.status(:building))

      expect(placement).to have_attributes(type: "started", name: "In Progress")
    end

    it "refuses a state nobody has placed, rather than guessing at one" do
      unplaced = SpecPlanBuild::Status.new(key: :invented, emoji: "🦆", label: "Invented",
        requires: [], note: "", invariant: nil)

      expect { described_class.placement(unplaced) }
        .to raise_error(SpecPlanBuild::Error, /no Linear placement/)
    end
  end

  describe ".key!" do
    it "accepts a team key however it was typed" do
      expect(described_class.key!(" tax ")).to eq("TAX")
    end

    it "rejects anything that could never be one, naming what a key looks like" do
      expect { described_class.key!("tax-team") }
        .to raise_error(SpecPlanBuild::Error, /not a Linear team key.*TAX-41/m)
    end
  end
end
