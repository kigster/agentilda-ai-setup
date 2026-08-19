# frozen_string_literal: true

module SpecPlanBuild
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
    # Tools no agent may use under this autonomy level, whatever its definition
    # asks for. Git itself is reachable through Bash, which is why the
    # after-check exists as well.
    DENIED_TOOLS = %w[WebFetch WebSearch].freeze

    # Shell fragments that mean "this is leaving the machine".
    FORBIDDEN_COMMANDS = /\bgit\s+(push|commit)\b|\bgh\s+(pr|release)\s+(create|edit|merge)\b/

    # @param root [String] the repository the agents work in
    # @param command [TTY::Command]
    # @param timeout [Integer] seconds before one agent is abandoned
    # @param dry_run [Boolean] plan the invocation, do not run it
    def initialize(root:, command: TTY::Command.new(printer: :null), timeout: 900, dry_run: false)
      @root = File.expand_path(root)
      @command = command
      @timeout = timeout
      @dry_run = dry_run
    end

    # @return [String]
    attr_reader :root

    # @param agent [SpecPlanBuild::Agent]
    # @param subject [SpecPlanBuild::Subject]
    # @return [Array(Boolean, String)] ok, and a one-line note
    def call(agent, subject, root: @root)
      return [true, "dry run — would invoke #{agent.name}"] if @dry_run

      before = head(root)

      begin
        @command.run(*invocation(agent, subject, root:), timeout: @timeout)
      rescue TTY::Command::TimeoutExceeded
        return [false, "timed out after #{@timeout}s"]
      rescue TTY::Command::ExitError => e
        return [false, "claude exited non-zero: #{e.message.lines.first.to_s.strip}"]
      end

      violation = boundary_violation(before, root)
      return [false, violation] if violation

      [true, "completed"]
    end

    # The exact argv, exposed so a spec can assert the boundary flags without
    # running anything.
    #
    # @param agent [SpecPlanBuild::Agent]
    # @param subject [SpecPlanBuild::Subject]
    # @return [Array<String>]
    def invocation(agent, subject, root: @root)
      argv = ["claude", "-p", prompt_for(agent, subject, root),
        "--add-dir", root,
        "--disallowedTools", DENIED_TOOLS.join(",")]
      argv += ["--allowedTools", agent.allowed_tools.join(",")] unless agent.allowed_tools.empty?
      argv += ["--model", agent.model] if agent.model
      argv
    end

    private

    # @param agent [SpecPlanBuild::Agent]
    # @param subject [SpecPlanBuild::Subject]
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
        markdown. You may NOT commit, push, or create or edit a pull request.
        The harness checks afterwards that HEAD has not moved, and a round that
        moved it is reported as a failure and rolled into the report.

        Claim what you are about to write with ~/.claude/agent-lock.sh first,
        and release it when you are done.
      PROMPT
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
