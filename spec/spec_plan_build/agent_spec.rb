# frozen_string_literal: true

RSpec.describe SpecPlanBuild::Agents do
  subject(:agents) { described_class.new(dir: dir) }

  let(:dir) { Dir.mktmpdir("spb-agents") }

  after { FileUtils.remove_entry(dir) if File.directory?(dir) }

  # @param body [String] the frontmatter, without the fences
  # @return [void]
  def define(body)
    File.write(File.join(dir, "tester.md"), "---\n#{body}\n---\n\nthe prompt\n")
  end

  let(:minimal) { "name: tester\nhandles: [new]\nadvances_to: researched" }

  describe "timeout" do
    # An agent that fans out subagents and one that reads a single diff differ
    # by more than an order of magnitude. The person starting a run has no way
    # to know which is which, so the agent says it, next to the rest of its
    # shape.
    it "reads a declared timeout" do
      define("#{minimal}\ntimeout: 5400")

      expect(agents.find("tester").timeout).to eq(5400)
    end

    it "is nil when the agent declares none, so the default applies" do
      define(minimal)

      expect(agents.find("tester").timeout).to be_nil
    end

    # `"soon".to_i` is 0, and a zero timeout abandons the agent the instant it
    # starts. A typo must fall back to the default, not to killing every run.
    it "falls back to the default when the value is not a number" do
      define("#{minimal}\ntimeout: soon")

      expect(agents.find("tester").timeout).to be_nil
    end

    it "falls back when the value is zero" do
      define("#{minimal}\ntimeout: 0")

      expect(agents.find("tester").timeout).to be_nil
    end

    it "falls back when the value is negative" do
      define("#{minimal}\ntimeout: -30")

      expect(agents.find("tester").timeout).to be_nil
    end
  end

  describe "the definitions this repository ships" do
    subject(:shipped) { described_class.new }

    # The regression. leah-researcher's prompt says research "may take an hour
    # or more"; the executor allowed 900s, so the agent was killed before it
    # wrote and every run of it reported a failed plan.
    it "gives leah-researcher longer than the default, as its own prompt asks for" do
      leah = shipped.find("leah-researcher")

      expect(leah.timeout).to be > SpecPlanBuild::Executor::DEFAULT_TIMEOUT
    end

    it "leaves the other specialists on the default" do
      others = shipped.all.reject { |a| a.name == "leah-researcher" }

      expect(others.map(&:timeout).compact).to be_empty
    end
  end
end
