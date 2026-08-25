# frozen_string_literal: true

RSpec.describe Agentilda::Executor, :tree do
  subject(:executor) { described_class.new(root:, command:) }

  let(:root) { File.dirname(plans_root) }
  let(:command) { instance_double(TTY::Command, run: nil) }
  let(:agents) { Agentilda::Agents.new }
  let(:agent) { agents.find("yoda-writer") }

  let!(:built) do
    plans { |t| t.plan "000.00", :new, "a-feature", files: {"spec.md" => spec_body} }
  end

  let(:subject_plan) { Agentilda::Tree.new(dir: plans_root).subjects.first }

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
    Agentilda::Agent.new(
      name: "x", description: "", handles: [:new], advances_to: :planned, model: nil,
      allowed_tools: [], may:, network:, prompt: "do it", path: "x.md"
    )
  end

  def denied(agent)
    described_class.new(root:, command:).invocation(agent, subject_plan)
      .each_cons(2).find { |flag, _| flag == "--disallowedTools" }&.last.to_s.split(",")
  end

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
    let(:hansolo) { Agentilda::Agents.new(dir: "agents").all.find { |a| a.name == "hansolo-reviewer" } }

    it "may review, which is the point of him" do
      expect(denied(hansolo)).not_to include("Bash(gh pr review:*)")
    end

    it "may not merge, which is the line" do
      expect(denied(hansolo)).to include("Bash(gh pr merge:*)", "Bash(git push:*)")
    end
  end

  # `claude -p` says nothing until it is finished, so a fifteen minute
  # invocation and a hung one look identical. Asked for the streaming format it
  # reports each tool call as it makes it, and this is what reads them.
  describe "streaming what the agent is doing" do
    subject(:streaming) { described_class.new(root:, command: streamer, trace_dir: @traces) }

    let(:seen) { [] }
    let(:chunks) { [] }

    let(:streamer) do
      instance_double(TTY::Command).tap do |double|
        allow(double).to receive(:run) { |*, **, &block| chunks.each { |chunk| block&.call(chunk, nil) } }
      end
    end

    around do |example|
      Dir.mktmpdir("executor-traces") do |dir|
        @traces = dir
        example.run
      end
    end

    def event(hash) = "#{JSON.generate(hash)}\n"

    def tool(name, input) = event(type: "assistant", message: {content: [{type: "tool_use", name:, input:}]})

    it "asks claude for the streaming format, which needs --verbose to work at all" do
      expect(streaming.invocation(agent, subject_plan).each_cons(2).to_a)
        .to include(["--output-format", "stream-json"])
        .and include(["stream-json", "--verbose"])
    end

    # A tool name is a noun and says nothing on its own. The spinner has room
    # for a phrase, so it gets one.
    it "hands each tool call to whoever is drawing the progress, as something being done" do
      chunks << tool("Read", {file_path: "/repo/spec.md"})
      streaming.call(agent, subject_plan) { |progress| seen << progress.activity }

      expect(seen).to eq(["reading spec.md"])
    end

    # Without it the stream reports a placeholder for what the model
    # generated — 2 for a four-thousand-token answer — and the counter on the
    # spinner line reads zero for the whole run.
    it "asks for partial messages, which is the only place a settled token count arrives" do
      expect(streaming.invocation(agent, subject_plan)).to include("--include-partial-messages")
    end

    it "reports what the invocation spent, not only whether it worked" do
      chunks << event(type: "stream_event",
        event: {type: "message_delta", usage: {input_tokens: 2, cache_creation_input_tokens: 100,
                                               cache_read_input_tokens: 900, output_tokens: 40}})

      expect(streaming.call(agent, subject_plan)).to have_attributes(up: 1002, down: 40)
    end

    # A run that burned two hundred thousand tokens before timing out is a
    # different fact from one that failed to authenticate and spent nothing.
    it "reports what a failed invocation spent too" do
      chunks << event(type: "stream_event",
        event: {type: "message_delta", usage: {input_tokens: 500, output_tokens: 7}})
      chunks << event(type: "result", is_error: true, result: "it went wrong")

      expect(streaming.call(agent, subject_plan)).to have_attributes(ok: false, up: 500, down: 7)
    end

    it "counts the sub-agents an agent spawned" do
      chunks << event(type: "system", subtype: "task_started", task_id: "t1", tool_use_id: "toolu_1")
      chunks << event(type: "system", subtype: "task_notification", task_id: "t1",
        usage: {total_tokens: 34_116})

      expect(streaming.call(agent, subject_plan)).to have_attributes(subagents: 1, delegated: 34_116)
    end

    it "runs perfectly well with nothing to report to" do
      chunks << tool("Read", {})

      expect(streaming.call(agent, subject_plan).ok).to be(true)
    end

    it "says how much work the agent did, rather than only that it finished" do
      chunks.push(tool("Read", {}), tool("Edit", {}))

      expect(streaming.call(agent, subject_plan).note).to eq("completed · 2 tool calls")
    end

    it "keeps the raw stream, so a run that went wrong can be read back" do
      chunks << event(type: "result", subtype: "success", result: "Folded B3.")
      streaming.call(agent, subject_plan)

      trace = Dir.children(@traces).grep(/\.ndjson\z/).first
      expect(File.read(File.join(@traces, trace))).to include("Folded B3.")
    end

    it "names the trace in the report when the run failed, since that is when it is wanted" do
      allow(streamer).to receive(:run).and_raise(TTY::Command::TimeoutExceeded)

      expect(streaming.call(agent, subject_plan).note).to include(".ndjson")
    end

    # Two agents run at once under `run -j`, and more than one agentilda
    # may be driving the same checkout.
    it "gives each invocation its own trace rather than one they share" do
      2.times { streaming.call(agent, subject_plan) }

      expect(Dir.children(@traces).size).to eq(2)
    end
  end
end
