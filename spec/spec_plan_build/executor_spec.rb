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
      expect(denied(agent)).to include(*described_class::DENIED_TOOLS)
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

    # A prompt is a request and a flag is a guarantee, so the agent gets both:
    # told what it may not do, and prevented from doing it.
    it "states the boundary in the prompt as well as enforcing it in flags" do
      expect(argv.join(" ")).to include("withheld from you, not merely discouraged", "gh pr merge")
    end
  end

  # The autonomy boundary is closed by default and opened per agent, in the
  # agent's own file. A researcher whose whole job is reading the internet was
  # otherwise handed --disallowedTools WebFetch,WebSearch on every invocation,
  # and duly ran, found nothing, and reported success.
  def agent_with(network: false, may: [])
    SpecPlanBuild::Agent.new(
      name: "x", description: "", handles: [:new], advances_to: :planned, model: nil,
      allowed_tools: [], may:, network:, prompt: "do it", path: "x.md"
    )
  end

  def denied(agent) = described_class.new(root:, command:).invocation(agent, subject_plan)
    .each_cons(2).find { |flag, _| flag == "--disallowedTools" }&.last.to_s.split(",")

  # A run whose agents all failed printed ten copies of the same escaped prompt
  # and never said why. The reason was in the parts of the error this now reads.
  describe ".failure_reason" do
    def exit_error(status:, stdout: "Nothing written", stderr: "Nothing written")
      TTY::Command::ExitError.new("claude -p …", instance_double(TTY::Command::Result,
        exit_status: status, out: stdout, err: stderr))
    end

    it "leads with what the agent said, not with the command that said it" do
      error = exit_error(status: 1, stdout: "Failed to authenticate. API Error: 401 API key is invalid.")

      expect(described_class.failure_reason(error))
        .to eq("exited 1: Failed to authenticate. API Error: 401 API key is invalid.")
    end

    # `claude` reports its own failure on stdout and warns on stderr, and in the
    # 401 case only stderr named the cause. Dropping either loses half the answer.
    it "keeps both streams, because they carry different halves of the reason" do
      error = exit_error(status: 1, stdout: "401 API key is invalid.",
        stderr: "ANTHROPIC_API_KEY takes precedence over your claude.ai login")

      expect(described_class.failure_reason(error))
        .to eq("exited 1: 401 API key is invalid. | ANTHROPIC_API_KEY takes precedence over your claude.ai login")
    end

    it "says so plainly when the agent exited without explaining itself" do
      expect(described_class.failure_reason(exit_error(status: 7))).to eq("exited 7 and said nothing")
    end

    it "keeps the reason to one report line" do
      error = exit_error(status: 1, stdout: "x" * 500)

      expect(described_class.failure_reason(error).length).to be <= described_class::REASON_LIMIT + 20
    end
  end

  describe ".foreign_credentials" do
    it "names the credentials an agent would authenticate with instead of the login" do
      expect(described_class.foreign_credentials({"ANTHROPIC_API_KEY" => "sk-ant-x"})).to eq(["ANTHROPIC_API_KEY"])
    end

    it "ignores one that is set to nothing, which is how a shell unsets it in practice" do
      expect(described_class.foreign_credentials({"ANTHROPIC_API_KEY" => "  "})).to be_empty
    end
  end

  describe "the network boundary" do
    it "denies the web to an agent that did not ask for it" do
      expect(denied(agent_with(network: false))).to include("WebFetch", "WebSearch")
    end

    it "grants it to one that did" do
      expect(denied(agent_with(network: true))).not_to include("WebFetch", "WebSearch")
    end

    it "defaults to closed when the definition says nothing" do
      expect(agent_with.network).to be(false)
    end

    # Opening the network does not open anything else.
    it "leaves the command boundary alone either way" do
      expect(denied(agent_with(network: true))).to include("Bash(git push:*)")
    end
  end

  # This list spent a while as a regular expression nothing referenced — a
  # guard in the shape of a constant. `gh pr review` was reachable by every
  # agent, and granted to none.
  describe "the command boundary" do
    it "withholds every forbidden command from an agent that asked for nothing" do
      expect(denied(agent_with)).to include(*described_class::FORBIDDEN_COMMANDS.map { |c| "Bash(#{c}:*)" })
    end

    it "lifts exactly what an agent's definition asks for" do
      argv = denied(agent_with(may: ["gh pr review"]))

      aggregate_failures do
        expect(argv).not_to include("Bash(gh pr review:*)")
        expect(argv).to include("Bash(gh pr comment:*)")
      end
    end

    # The line between approving and merging. An approval is reversible,
    # visible and attributable; a merge changes a branch everyone builds on.
    it "refuses to lift a merge or a push, however the definition is written" do
      argv = denied(agent_with(may: ["gh pr merge", "git push", "gh pr review"]))

      aggregate_failures do
        expect(argv).to include("Bash(gh pr merge:*)", "Bash(git push:*)")
        expect(argv).not_to include("Bash(gh pr review:*)")
      end
    end

    it "tells the agent what it has been granted, not only what it has lost" do
      argv = described_class.new(root:, command:).invocation(agent_with(may: ["gh pr review"]), subject_plan)

      expect(argv.join(" ")).to include("You may run these, which most agents may not", "gh pr review")
    end

    it "says nothing about grants to an agent that has none" do
      argv = described_class.new(root:, command:).invocation(agent_with, subject_plan)

      expect(argv.join(" ")).not_to include("which most agents may not")
    end
  end

  describe "hansolo-reviewer, as the repository actually defines him" do
    let(:hansolo) { SpecPlanBuild::Agents.new(dir: "agents").all.find { |a| a.name == "hansolo-reviewer" } }

    it "may review, which is the point of him" do
      expect(denied(hansolo)).not_to include("Bash(gh pr review:*)")
    end

    it "may not merge, which is the line" do
      expect(denied(hansolo)).to include("Bash(gh pr merge:*)", "Bash(git push:*)")
    end
  end
end
