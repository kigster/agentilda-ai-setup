# frozen_string_literal: true

require "tmpdir"

# `pull-requests.md` is written by `create --prs` and read back by the state
# machine, so the two halves have to agree exactly. Every example here is a
# round trip rather than a string comparison: what matters is not how the
# markdown looks but that the parser recovers what the renderer put in.
RSpec.describe SpecPlanBuild::PullRequests do
  def round_trip(prs)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, described_class::FILENAME), described_class.render(prs))
      described_class.new(dir:).all
    end
  end

  def pr(number:, title: "A change", state: "Merged 🟣", body: "It did a thing.")
    {number:, title:, state:, body:, url: "https://github.com/o/r/pull/#{number}"}
  end

  describe ".render" do
    it "recovers every pull request it wrote" do
      recovered = round_trip([pr(number: 12), pr(number: 15, state: "Open 🟡")])

      expect(recovered.map { |p| [p.number, p.state] }).to eq([["12", "Merged 🟣"], ["15", "Open 🟡"]])
    end

    # A pipe ends a cell, and "guard against a || b" is an ordinary title.
    it "survives a title containing a table delimiter" do
      recovered = round_trip([pr(number: 12, title: "Guard against a || b")])

      expect(recovered.first.title).to eq("Guard against a || b")
    end

    it "keeps the state machine's vocabulary, so the folder can be judged by it" do
      recovered = round_trip([pr(number: 12, state: "Merged 🟣")])

      expect(recovered.first).to be_merged
    end

    # The bodies are the raw material a retroactive spec.md is written from —
    # a specification cannot be synthesized from a list of numbers.
    it "writes each description below the table, where the parser ignores it" do
      rendered = described_class.render([pr(number: 12, body: "Adds /healthz and /readyz.")])

      aggregate_failures do
        expect(rendered).to include("Adds /healthz and /readyz.")
        expect(round_trip([pr(number: 12, body: "Adds /healthz and /readyz.")]).size).to eq(1)
      end
    end

    it "says so plainly when a pull request carried no description" do
      expect(described_class.render([pr(number: 12, body: "")])).to match(/No description was written/)
    end
  end
end
