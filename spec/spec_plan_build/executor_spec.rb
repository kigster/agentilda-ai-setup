# frozen_string_literal: true

RSpec.describe SpecPlanBuild::Executor, :tree do
  subject(:executor) { described_class.new(root:, command:) }

  let(:root) { File.dirname(plans_root) }
  let(:command) { instance_double(TTY::Command, run: nil) }
  let(:agents) { SpecPlanBuild::Agents.new }
  let(:agent) { agents.find("yoda-writer") }

  let!(:built) do
    plans { |t| t.plan "000.00", :new, "a-feature", files: {"spec.md" => spec_body} }
  end

  let(:subject_plan) { SpecPlanBuild::Tree.new(dir: plans_root).subjects.first }

  describe "#invocation" do
    let(:argv) { executor.invocation(agent, subject_plan) }

    it "withholds the tools that would let an agent reach off the machine" do
      expect(argv.each_cons(2).to_a).to include(["--disallowedTools", described_class::DENIED_TOOLS.join(",")])
    end

    it "passes through the tools the agent's definition allows" do
      expect(argv.each_cons(2).to_a).to include(["--allowedTools", agent.allowed_tools.join(",")])
    end

    it "scopes the agent to the repository it is working in" do
      expect(argv.each_cons(2).to_a).to include(["--add-dir", root])
    end

    it "tells the agent which plan it has, and what is wrong with it" do
      expect(argv.join(" ")).to include("000.00").and include(subject_plan.feature.path)
    end

    it "states the boundary in the prompt as well as enforcing it in flags" do
      expect(argv.join(" ")).to match(/may NOT commit, push/)
    end
  end

  # The autonomy boundary is closed by default and opened per agent, in the
  # agent's own file. A researcher whose whole job is reading the internet was
  # otherwise handed --disallowedTools WebFetch,WebSearch on every invocation,
  # and duly ran, found nothing, and reported success.
  describe "the network boundary" do
    def agent_with(network:)
      SpecPlanBuild::Agent.new(
        name: "x", description: "", handles: [:new], advances_to: :planned, model: nil,
        allowed_tools: [], forbids: [], network:, prompt: "do it", path: "x.md"
      )
    end

    it "denies the web to an agent that did not ask for it" do
      argv = described_class.new(root:, command:).invocation(agent_with(network: false), subject_plan)

      expect(argv.each_cons(2).to_a).to include(["--disallowedTools", "WebFetch,WebSearch"])
    end

    it "grants it to one that did" do
      argv = described_class.new(root:, command:).invocation(agent_with(network: true), subject_plan)

      expect(argv).not_to include("--disallowedTools")
    end

    it "defaults to closed when the definition says nothing" do
      expect(agent_with(network: false).network).to be(false)
    end

    # Opening the network does not open anything else: the harness still
    # checks afterwards that HEAD did not move.
    it "leaves the commit boundary alone either way" do
      argv = described_class.new(root:, command:).invocation(agent_with(network: true), subject_plan)

      expect(argv).to include("--add-dir")
    end
  end
end
