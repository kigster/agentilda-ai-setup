# frozen_string_literal: true

module Agentilda
  # Runs one agent against one plan by shelling out to the `claude` CLI.
  #
  # The autonomy boundary is "docs plus code, but nothing leaves the machine",
  # and it is enforced twice over:
  #
  #   BEFORE — the agent is told, and `--disallowedTools` withholds the tools
  #            that would let it push.
  #   AFTER  — the harness checks that HEAD did not move and no new remote ref
  #            appeared. A prompt is a request; a check is a guarantee, and only
  #            one of them survives a model deciding it knows better.
  class Executor
    # What one invocation did, and what it spent doing it.
    #
    # {#to_ary} is deliberate: every caller of {Executor#call} destructures
    # `ok, note = executor.call(...)`, and the meter is an addition to that
    # answer rather than a replacement for it. Callers that want the tokens
    # ask for them by name.
    #
    # @!attribute [r] ok
    #   @return [Boolean]
    # @!attribute [r] note
    #   @return [String] one line, for the report
    # @!attribute [r] up
    #   @return [Integer] tokens sent, sub-agents included
    # @!attribute [r] down
    #   @return [Integer] tokens generated
    # @!attribute [r] subagents
    #   @return [Integer] sub-agents this agent spawned
    # @!attribute [r] delegated
    #   @return [Integer] of {#up}, how much arrived as an unsplit sub-agent
    #     total rather than as a direction of its own
    # @!attribute [r] seconds
    #   @return [Float] wall clock, from argv to exit
    Result = Data.define(:ok, :note, :up, :down, :subagents, :delegated, :seconds) do
      # @return [Array(Boolean, String)]
      def to_ary = [ok, note]
    end

    # Tools no agent may use under this autonomy level, whatever its definition
    # asks for. Git itself is reachable through Bash, which is why the
    # after-check exists as well.
    #
    # The exception is an agent that declares `network: true`. Closed is the
    # right default — most specialists here read the repository and write to
    # it, and a model that decides to go looking online mid-task is a model
    # doing something nobody asked for. But a researcher inverts that: reading
    # the internet is the entire job, and denying it silently produced an
    # agent that ran, found nothing, and reported success.
    DENIED_TOOLS = %w[WebFetch WebSearch].freeze

    # Commands that leave the machine, denied to every agent by default.
    #
    # These are passed to `claude` as `Bash(<command>:*)` tool specifiers, so
    # they are withheld rather than merely discouraged. This list spent a while
    # as a regular expression that nothing referenced — a guard in the shape of
    # a constant, enforcing nothing — which is exactly how `gh pr review` came
    # to be reachable by an agent nobody had granted it to.
    FORBIDDEN_COMMANDS = [
      "git push", "git commit",
      "gh pr create", "gh pr edit", "gh pr merge",
      "gh pr review", "gh pr comment",
      "gh release create"
    ].freeze

    # The subset no agent's `may:` can lift, however its definition is written.
    #
    # Pushing and merging change a branch everybody else builds on, and an
    # unattended loop doing either has no way to be wrong quietly. Reviewing
    # does not: an approval is reversible, visible, and attributable to the
    # identity that made it. That difference is the whole line between
    # `hansolo-reviewer` approving and `hansolo-reviewer` merging.
    UNGRANTABLE = ["git push", "gh pr merge"].freeze

    # The `stdout:` and `stderr:` sections of a {TTY::Command::ExitError}
    # message. stdout runs until stderr starts; stderr runs to the end, because
    # what an agent prints there is not guaranteed to be one line.
    STDOUT_SECTION = /^[ \t]*stdout:[ \t]*(.*?)(?=\n[ \t]*stderr:|\z)/m
    STDERR_SECTION = /^[ \t]*stderr:[ \t]*(.*)\z/m

    # How much of what the agent said survives into a one-line report.
    REASON_LIMIT = 300

    # Where the raw stream of each invocation is kept.
    #
    # Under `run -j` several agents work at once, and more than one
    # `agentilda` may be driving the same checkout, so a trace is named
    # per invocation rather than shared. To get an agent's final answer back
    # out of one afterwards:
    #
    #   jq -r 'select(.type=="result").result' <trace>
    #
    # and to replay what it did, tool call by tool call:
    #
    #   jq -r 'select(.type=="assistant")
    #          | .message.content[]?
    #          | select(.type=="tool_use")
    #          | "\(.name) \(.input|tostring[0:80])"' <trace>
    #
    # Outside the repository on purpose: the harness checks afterwards that the
    # agent moved nothing it should not have, and a megabyte of NDJSON dropped
    # into the working tree is exactly the kind of thing that check would then
    # have to learn to ignore.
    TRACE_DIR = File.join(Dir.tmpdir, "agentilda-traces")

    # Environment variables the `claude` CLI reads as credentials, in
    # preference to a claude.ai login.
    #
    # A project `.env` that sets one of these for the application's own use
    # reaches every agent a run spawns. `claude` then authenticates with that
    # key rather than the login, and a stale or unrelated one turns an entire
    # run into `401 API key is invalid`, three minutes per agent. The CLI warns
    # rather than unsets. Driving it with an API key on purpose is legitimate,
    # and nothing here can tell the two apart.
    CREDENTIAL_VARS = %w[ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN].freeze

    # @param env [Hash]
    # @return [Array<String>] credential variables currently set
    def self.foreign_credentials(env = ENV)
      CREDENTIAL_VARS.reject { |name| env[name].to_s.strip.empty? }
    end

    # What `claude` said, out of the four labelled sections
    # {TTY::Command::ExitError} builds its message from.
    #
    # The first of those sections is the command line, which for an agent is a
    # shell-escaped copy of its several-thousand-character prompt. Reporting it
    # said that an invocation had failed, at length, and nothing at all about
    # why. The run that found this printed the same escaped prompt ten times
    # while the answer, `401 API key is invalid`, sat unread in `stdout:`.
    #
    # This keeps both streams, because they carry different halves. `claude`
    # reports its own failures on stdout; the line naming the *cause* of that
    # 401 (`ANTHROPIC_API_KEY … takes precedence over your claude.ai login`)
    # was on stderr.
    #
    # @param error [TTY::Command::ExitError]
    # @return [String]
    def self.failure_reason(error)
      status = error.message[/^[ \t]*exit status:[ \t]*(\S+)/, 1]
      outcome = status ? "exited #{status}" : "failed"
      said = [STDOUT_SECTION, STDERR_SECTION]
        .filter_map { |section| tail(error.message[section, 1]) }
        .join(" | ")

      said.empty? ? "#{outcome} and said nothing" : "#{outcome}: #{said}"
    end

    # @param text [String, nil]
    # @return [String, nil] the last few meaningful lines, on one line
    def self.tail(text)
      lines = text.to_s.split("\n").map(&:strip).reject { |line| line.empty? || line == "Nothing written" }
      return nil if lines.empty?

      joined = lines.last(3).join(" ")
      (joined.length > REASON_LIMIT) ? "#{joined[0, REASON_LIMIT - 1]}…" : joined
    end
    private_class_method :tail

    # What went wrong, preferring what the stream managed to parse.
    #
    # `claude` reports its own failures two different ways. A run that got far
    # enough emits a `result` event saying so, and that is the readable one. A
    # run that failed before it started — the 401 that cost a whole round three
    # minutes an agent — prints prose on stdout and never emits an event at
    # all, so those lines are what {Transcript#plain} holds and what is left to
    # report. {.failure_reason} stays the last resort, for a failure that
    # printed nothing either way.
    #
    # @param error [TTY::Command::ExitError]
    # @param transcript [Agentilda::Transcript]
    # @return [String]
    def reason_for(error, transcript)
      return "failed: #{transcript.error}" if transcript.failed?

      said = transcript.plain.last(3).join(" ")
      said.empty? ? self.class.failure_reason(error) : "failed: #{said}"
    end

    # @param root [String] the repository the agents work in
    # @param command [TTY::Command]
    # @param timeout [Integer] seconds before one agent is abandoned
    # @param dry_run [Boolean] plan the invocation, do not run it
    # @param trace_dir [String] where each invocation's raw stream is kept
    def initialize(root:, command: TTY::Command.new(printer: :null), timeout: 900, dry_run: false,
      trace_dir: TRACE_DIR)
      @root = File.expand_path(root)
      @command = command
      @timeout = timeout
      @dry_run = dry_run
      @trace_dir = trace_dir
    end

    # @return [String]
    attr_reader :root

    # @param agent [Agentilda::Agent]
    # @param subject [Agentilda::Subject]
    # @return [Agentilda::Executor::Result] whether it worked, a one-line
    #   note, and what it spent. Destructures as `ok, note` for callers that
    #   want no more than that.
    # @yieldparam progress [Agentilda::Transcript::Progress] what the
    #   agent is doing and what it has spent, as both change
    def call(agent, subject, root: @root, &on_progress)
      started = UI.monotonic
      if @dry_run
        return Result.new(ok: true, note: "dry run — would invoke #{agent.name}", up: 0, down: 0,
          subagents: 0, delegated: 0, seconds: 0.0)
      end

      before = head(root)
      trace = trace_path(agent, subject)
      transcript = Transcript.new(trace:, &on_progress)

      begin
        @command.run(*invocation(agent, subject, root:), timeout: @timeout) do |out, _err|
          transcript.push(out)
        end
        transcript.finish
      rescue TTY::Command::TimeoutExceeded
        transcript.finish
        return failure(transcript, started,
          "timed out after #{@timeout}s, last seen #{transcript.activity || "starting up"} — trace: #{trace}")
      rescue TTY::Command::ExitError => e
        transcript.finish
        return failure(transcript, started, "claude #{reason_for(e, transcript)} — trace: #{trace}")
      end

      if transcript.failed?
        return failure(transcript, started, "claude reported: #{transcript.error} — trace: #{trace}")
      end

      violation = boundary_violation(before, root)
      return failure(transcript, started, violation) if violation

      spent(transcript, started, ok: true,
        note: "completed#{" · #{transcript.tools} tool calls" if transcript.tools.positive?}")
    end

    # A failed invocation still spent what it spent, and a run that burned two
    # hundred thousand tokens before timing out is a different fact from one
    # that failed to authenticate and spent nothing. Both used to report the
    # same thing.
    #
    # @param transcript [Agentilda::Transcript]
    # @param started [Float]
    # @param note [String]
    # @return [Agentilda::Executor::Result]
    def failure(transcript, started, note) = spent(transcript, started, ok: false, note:)

    # @param transcript [Agentilda::Transcript]
    # @param started [Float]
    # @param ok [Boolean]
    # @param note [String]
    # @return [Agentilda::Executor::Result]
    def spent(transcript, started, ok:, note:)
      Result.new(ok:, note:, up: transcript.up, down: transcript.down,
        subagents: transcript.spawned, delegated: transcript.delegated,
        seconds: UI.monotonic - started)
    end

    # The exact argv, exposed so a spec can assert the boundary flags without
    # running anything.
    #
    # @param agent [Agentilda::Agent]
    # @param subject [Agentilda::Subject]
    # @return [Array<String>]
    def invocation(agent, subject, root: @root)
      # `--include-partial-messages` is what the token meter runs on. Without
      # it the stream reports a settled input count and a placeholder output
      # count — 2 for a four-thousand-token answer — and a spinner counting
      # what came back would read zero all run. See {Transcript#meter}.
      argv = ["claude", "-p", prompt_for(agent, subject, root), "--add-dir", root,
        "--output-format", "stream-json", "--verbose", "--include-partial-messages"]
      denied = denied_for(agent)
      argv += ["--disallowedTools", denied.join(",")] unless denied.empty?
      argv += ["--allowedTools", agent.allowed_tools.join(",")] unless agent.allowed_tools.empty?
      argv += ["--model", agent.model] if agent.model
      argv
    end

    # What this particular agent may not touch: the network tools unless it
    # asked for them, plus every forbidden command it has not been granted.
    # Both decisions are recorded in a reviewable file rather than passed as a
    # flag by whoever happened to start the run.
    #
    # @param agent [Agentilda::Agent]
    # @return [Array<String>]
    def denied_for(agent)
      tools = agent.network ? [] : DENIED_TOOLS
      tools + denied_commands(agent).map { |command| "Bash(#{command}:*)" }
    end

    # @param agent [Agentilda::Agent]
    # @return [Array<String>] commands withheld from this agent
    def denied_commands(agent) = FORBIDDEN_COMMANDS - granted_to(agent)

    # @param agent [Agentilda::Agent]
    # @return [Array<String>] what its `may:` actually buys it
    def granted_to(agent) = agent.may - UNGRANTABLE

    private

    # One file per invocation. The plan number and the agent's name make it
    # findable; the pid and the clock keep two concurrent runs from writing to
    # the same one. See {TRACE_DIR} for how to read one back.
    #
    # @param agent [Agentilda::Agent]
    # @param subject [Agentilda::Subject]
    # @return [String]
    def trace_path(agent, subject)
      FileUtils.mkdir_p(@trace_dir)
      name = format("%s-%s-%s-%d-%04x.ndjson", Time.now.strftime("%Y%m%d-%H%M%S"),
        subject.feature.ordinal, agent.name, Process.pid, rand(0x10000))
      File.join(@trace_dir, name)
    end

    # @param agent [Agentilda::Agent]
    # @param subject [Agentilda::Subject]
    # @return [String]
    def prompt_for(agent, subject, root = @root)
      <<~PROMPT
        #{agent.prompt}

        ---

        ## This invocation

        Plan folder    : #{subject.feature.path}
        Plan number    : #{subject.feature.ordinal}
        Current state  : #{subject.status.emoji} #{subject.status.label}
        Repository root: #{root}

        #{"The folder's name is not currently justified: #{subject.violation}" if subject.violation}

        ## Boundary — enforced, not requested

        You may read anything, and write source, tests and the plan's own
        markdown.

        These are withheld from you, not merely discouraged — `claude` is
        invoked with them disallowed:

        #{denied_commands(agent).map { |c| "  #{c}" }.join("\n")}
        #{granted(agent)}
        The harness checks afterwards that HEAD has not moved, and a round that
        moved it is reported as a failure and rolled into the report. A prompt
        is a request; a check is a guarantee.

        Claim what you are about to write with ~/.claude/agent-lock.sh first,
        and release it when you are done.
      PROMPT
    end

    # Spelled out in the prompt as well as withheld at the tool layer, because
    # an agent that does not know it has been granted something does not use
    # it — and `hansolo-reviewer` silently never approving anything looks
    # exactly like `hansolo-reviewer` approving nothing worth approving.
    #
    # @param agent [Agentilda::Agent]
    # @return [String]
    def granted(agent)
      granted = granted_to(agent)
      return "" if granted.empty?

      "\nYou may run these, which most agents may not:\n\n" +
        granted.map { |c| "  #{c}" }.join("\n") + "\n"
    end

    # @return [String, nil] current commit, or nil outside a repository
    def head(root = @root)
      out = `git -C #{root.shellescape} rev-parse HEAD 2>/dev/null`.strip
      out.empty? ? nil : out
    end

    # @param before [String, nil]
    # @return [String, nil] what boundary was crossed, or nil
    def boundary_violation(before, root = @root)
      return nil if before.nil?

      after = head(root)
      return "agent committed (HEAD moved #{before[0, 7]} → #{after[0, 7]}) — the boundary is docs plus code, no commits" if after != before

      nil
    end
  end
end
