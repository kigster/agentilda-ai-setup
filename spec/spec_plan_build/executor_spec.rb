# frozen_string_literal: true

RSpec.describe SpecPlanBuild::Executor, :tree do
  subject(:executor) { described_class.new(root:, command:) }

  let(:root) { File.dirname(plans_root) }
  let(:command) { instance_double(TTY::Command, run: nil) }
  let(:agents) { SpecPlanBuild::Agents.new }
  let(:agent) { agents.find("spec-writer") }

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
end
