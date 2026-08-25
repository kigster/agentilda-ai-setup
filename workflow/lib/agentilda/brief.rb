# frozen_string_literal: true

module Agentilda
  # A new plan's opening brief: four questions, and a best-effort first pass
  # at answering them from what the project already has on disk.
  #
  # This is for work that does not exist yet. A plan created `--after` a
  # shipped pull request already has its facts — {CLI::Create} hands those to
  # `yoda-writer`, which reconstructs a specification from a diff, not this.
  # Guessing at a diff and guessing at a feature nobody has built are
  # different jobs, and conflating them is how a retroactive spec ends up
  # full of hedges about something that already, provably, happened.
  #
  # The four headings are the brief `leah-researcher` and `yoda-writer` both
  # read *before* their own chapters: what research needs to settle is a
  # question about the gaps in `## What already exists`, so a scaffold
  # missing that heading forces both of them to first reconstruct a boundary
  # this class already had for free — it just created the folder.
  class Brief
    HEADINGS = [
      "What we are trying to achieve",
      "Why it matters",
      "What already exists",
      "What research needs to settle"
    ].freeze

    # Read whole into the drafting prompt, in order, so the model sees the
    # project's own account of itself before it sees the topic.
    CONTEXT_FILES = %w[CLAUDE.md AGENTS.md README.md].freeze

    # Relative to the repository root. Not every project keeps one — a
    # missing backlog is silently skipped, not an error.
    BACKLOG_FILE = File.join(Agentilda::PLANS_DIR, "BACKLOG.md")

    # Long enough for a handful of Read/Grep/Glob calls over a local
    # checkout; short enough that a hung `claude` does not stall `create`
    # past the point where the scaffold is already there to open by hand.
    TIMEOUT = 240

    # Read-only, and no `Bash` — this pass surveys what the repository
    # already says about itself, it does not go looking further. That is
    # `leah-researcher`'s job, and denying her tools here is what keeps the
    # two from quietly doing the same work twice.
    ALLOWED_TOOLS = %w[Read Grep Glob Edit].freeze
    DENIED_TOOLS = %w[WebFetch WebSearch Bash].freeze

    # @param path [String] the new plan folder, absolute
    # @param title [String] the feature's proper name, e.g. "Tax Rule DSL"
    # @param root [String] repository root, for project context and `--add-dir`
    # @param command [TTY::Command]
    # @param timeout [Integer] seconds before the drafting attempt is abandoned
    # @param dry_run [Boolean] plan the invocation, do not run it
    def initialize(path:, title:, root:, command: TTY::Command.new(printer: :null), timeout: TIMEOUT, dry_run: false)
      @path = path
      @title = title
      @root = File.expand_path(root)
      @command = command
      @timeout = timeout
      @dry_run = dry_run
    end

    # @return [String]
    attr_reader :path, :title, :root

    # @return [String] absolute path to the spec, whether or not it exists yet
    def spec_path = File.join(path, "spec.md")

    # @return [String] the title and four empty headings, nothing else
    def scaffold
      "# #{title}\n\n" + HEADINGS.map { |h| "## #{h}\n\n" }.join("\n")
    end

    # @return [String] where it was written
    def write_scaffold!
      File.write(spec_path, scaffold)
      spec_path
    end

    # Make a best-effort attempt at the four headings, in place, by shelling
    # out to `claude` the same way {Executor} does for a specialist agent.
    # A failure here is not this method's to hide: the scaffold {#write_scaffold!}
    # already wrote stands on its own, so the caller reports the failure and
    # moves on rather than treating it as fatal to `create`.
    #
    # @return [Array(Boolean, String)] ok, and a one-line note
    def attempt!
      return [true, "dry run — would draft from project context"] if @dry_run

      begin
        @command.run(*invocation, timeout: @timeout)
      rescue TTY::Command::TimeoutExceeded
        return [false, "timed out after #{@timeout}s"]
      rescue TTY::Command::ExitError => e
        return [false, "claude #{Executor.failure_reason(e)}"]
      end

      [true, "drafted"]
    end

    # Exposed so a spec can assert the boundary without running anything.
    #
    # @return [Array<String>]
    def invocation
      ["claude", "-p", prompt, "--add-dir", root,
        "--allowedTools", ALLOWED_TOOLS.join(","),
        "--disallowedTools", DENIED_TOOLS.join(",")]
    end

    private

    # @return [String]
    def prompt
      <<~PROMPT
        A new plan folder was just created for a feature that does not exist
        yet: "#{title}".

        #{spec_path} holds a title and four empty headings:

        #{HEADINGS.map { |h| "  * #{h}" }.join("\n")}

        Make a best-effort first pass at each, drawn only from what THIS
        project already has on disk under #{root} — its own docs, its own
        conventions, code already built, and anything already downloaded or
        gathered that bears on "#{title}". Read/Grep/Glob freely to look for
        it; do not invent facts and do not research the web. Where the
        repository gives you nothing to go on, leave that heading's body as
        a short, honest one-line note saying so, e.g. "_Nothing in the repo
        speaks to this yet — needs research._" A human completes this
        afterward, and a confident-sounding guess costs them more to unwind
        than an honest blank.

        `## What already exists` matters most: name specific files, modules
        or prior work you found, not just that "some code exists" — that is
        exactly the context a researcher picking this up next cannot see for
        themselves without being told where to look.

        #{context}
        #{backlog}
        Edit #{spec_path} in place. Keep the title and the four `##`
        headings exactly as they are, in order; add prose under them; write
        nothing outside them; touch no other file.
      PROMPT
    end

    # @return [String]
    def context
      found = CONTEXT_FILES.filter_map { |name|
        file = File.join(root, name)
        next unless File.file?(file)

        "### #{name}\n\n#{File.read(file, encoding: "UTF-8")}"
      }
      return "" if found.empty?

      "## Project context\n\n#{found.join("\n\n")}\n"
    end

    # A relevant line in the project's own backlog is worth more than
    # anything this pass could infer on its own — it is the one place "why
    # now" might already be written down.
    #
    # @return [String]
    def backlog
      file = File.join(root, BACKLOG_FILE)
      return "" unless File.file?(file)

      "## #{BACKLOG_FILE}\n\n#{File.read(file, encoding: "UTF-8")}\n"
    end
  end
end
