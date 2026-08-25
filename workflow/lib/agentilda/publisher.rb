# frozen_string_literal: true

module Agentilda
  # Turns a finished worktree into a pushed branch and a pull request.
  #
  # This is the one place the harness reaches off the machine, so it requires
  # `--commit`, is skipped with `--dont-push-anything`, and refuses anything
  # it is not certain about. Everything it does is reported before it does it.
  #
  # Titles follow the convention the whole system joins on:
  #
  #     [002.00](A) Tenancy Households       — a plan's first pull request
  #     [002.00](B) Tenancy Households       — its second
  #
  # The slug is title-cased from the folder name, so the title reads as a
  # sentence rather than as a path fragment.
  class Publisher
    # A published, or publishable, pull request.
    #
    # @!attribute [r] ordinal
    #   @return [Agentilda::Ordinal]
    # @!attribute [r] branch
    #   @return [String]
    # @!attribute [r] title
    #   @return [String]
    # @!attribute [r] url
    #   @return [String, nil] nil on a dry run or a refusal
    # @!attribute [r] refusal
    #   @return [String, nil]
    Publication = Data.define(:ordinal, :branch, :title, :url, :refusal) do
      # @return [Boolean]
      def published? = !url.nil?
    end

    # A..Z, which is more parts than any feature should be split into.
    LETTERS = ("A".."Z").to_a.freeze

    # @param root [String] repository the worktree belongs to
    # @param command [TTY::Command]
    # @param base [String] the branch pull requests target
    # @param dry_run [Boolean]
    def initialize(root:, command: TTY::Command.new(printer: :null), base: "main", dry_run: true)
      @root = root
      @command = command
      @base = base
      @dry_run = dry_run
    end

    # Push one plan's branch and open its pull request.
    #
    # @param checkout [Agentilda::Worktree::Checkout]
    # @param subject [Agentilda::Subject]
    # @param letter [String, nil] force a part letter; nil auto-assigns
    # @return [Agentilda::Publisher::Publication]
    def publish(checkout:, subject:, letter: nil)
      title = title_for(subject, letter)

      unless checkout.dirty?
        return refuse(subject, checkout, title, "nothing to publish — the worktree is unchanged")
      end

      return Publication.new(**base_fields(subject, checkout, title), url: nil, refusal: nil) if @dry_run

      commit(checkout, title)
      push(checkout)
      url = create_pull_request(checkout, subject, title)

      Publication.new(**base_fields(subject, checkout, title), url:, refusal: nil)
    rescue TTY::Command::ExitError => e
      refuse(subject, checkout, title, git_complaint(e))
    end

    # git and gh put the useful sentence in stderr, several lines below the
    # command they echo. Reporting only the first line reports "it failed".
    #
    # @param error [TTY::Command::ExitError]
    # @return [String]
    def git_complaint(error)
      lines = error.message.lines.map(&:strip).reject(&:empty?)
      stderr = lines.find { |l| l.start_with?("stderr:") }
      complaint = stderr&.delete_prefix("stderr:")&.strip

      (complaint.to_s.empty? || complaint == "Nothing written") ? lines.first.to_s : complaint
    end

    # The title a plan's next pull request should carry.
    #
    # @param subject [Agentilda::Subject]
    # @param letter [String, nil]
    # @return [String]
    def title_for(subject, letter = nil)
      "[#{subject.feature.ordinal}](#{letter || auto_letter(subject)}) #{subject.feature.title}"
    end

    # Which part this is. Always a letter, starting at A: a plan that turns out
    # to need only one pull request still reads consistently with every other,
    # and nothing has to be renamed when a second arrives.
    #
    # @param subject [Agentilda::Subject]
    # @return [String]
    def auto_letter(subject) = LETTERS.fetch(subject.pull_requests.size, LETTERS.last)

    private

    # @return [Hash]
    def base_fields(subject, checkout, title)
      {ordinal: subject.feature.ordinal, branch: checkout.branch, title:}
    end

    # @return [Agentilda::Publisher::Publication]
    def refuse(subject, checkout, title, why)
      Publication.new(**base_fields(subject, checkout, title), url: nil, refusal: why)
    end

    # @param checkout [Agentilda::Worktree::Checkout]
    # @param title [String]
    # @return [void]
    def commit(checkout, title)
      run(checkout, "git", "add", "-A")
      # The subject line drops the bracketed prefix: it belongs in the pull
      # request title, where things join on it, not in every commit message.
      run(checkout, "git", "commit", "-m", title.sub(/\A\[[^\]]+\](?:\([A-Z]\))?\s*/, ""))
    end

    # @param checkout [Agentilda::Worktree::Checkout]
    # @return [void]
    def push(checkout) = run(checkout, "git", "push", "-u", "origin", checkout.branch)

    # @return [String, nil] the pull request URL
    def create_pull_request(checkout, subject, title)
      Tempfile.create(["pr", ".md"]) do |file|
        file.write(description(subject, title))
        file.flush
        result = run(checkout, "gh", "pr", "create", "-a", "@me", "-B", @base, "-t", title, "-F", file.path)
        return result.out.to_s[%r{https://\S+}]
      end
    end

    # The body `/create-pr` would have written: a title line, a summary lifted
    # from the specification, and a link back to the plan folder so a reviewer
    # can find the rest.
    #
    # @return [String]
    def description(subject, title)
      <<~MARKDOWN
        # #{title}

        ## Summary

        #{summary_text(subject)}

        ## Plan

        Implements `#{subject.feature.dirname}`. The specification and the plan
        for this work live in that folder.
      MARKDOWN
    end

    # The specification's own Goal section, verbatim. A pull request body that
    # paraphrases the spec is a second copy that drifts; quoting it is not.
    #
    # @param subject [Agentilda::Subject]
    # @return [String]
    def summary_text(subject)
      text = subject.goal.join("\n\n")
      text.empty? ? "See `#{subject.feature.dirname}/spec.md`." : text
    end

    # @return [TTY::Command::Result]
    def run(checkout, *argv) = @command.run(*argv, chdir: checkout.path)
  end
end
