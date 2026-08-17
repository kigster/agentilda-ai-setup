# frozen_string_literal: true

require "json"

module SpecPlanBuild
  # The `gh` CLI, wrapped thinly.
  #
  # It is a seam rather than a convenience: every example in the suite injects
  # a double here, so nothing in the tests reaches the network or a real
  # repository.
  class GitHub
    # Fields asked of `gh pr list`.
    FIELDS = %w[number title url headRefName files].freeze

    # @param command [TTY::Command] runner, injectable for tests
    # @param limit [Integer] how many pull requests to fetch
    def initialize(command: TTY::Command.new(printer: :null), limit: 200)
      @command = command
      @limit = limit
    end

    # Every pull request, normalised into plain hashes.
    #
    # @param state [String] "open", "closed", "merged" or "all"
    # @return [Array<Hash>] `{number:, title:, url:, branch:, files:}`
    def pulls(state: "all")
      out = @command.run("gh", "pr", "list", "--state", state, "--limit", @limit.to_s,
        "--json", FIELDS.join(",")).out
      JSON.parse(out).map do |pr|
        {
          number: pr["number"],
          title: pr["title"].to_s,
          url: pr["url"],
          branch: pr["headRefName"].to_s,
          files: Array(pr["files"]).map { |f| f["path"] }.compact
        }
      end
    rescue TTY::Command::ExitError, JSON::ParserError => e
      raise Error, "could not list pull requests via `gh`: #{e.message.lines.first.to_s.strip}"
    end

    # Change a pull request's title.
    #
    # @param number [Integer]
    # @param title [String]
    # @return [void]
    def retitle(number:, title:)
      @command.run("gh", "pr", "edit", number.to_s, "--title", title)
    rescue TTY::Command::ExitError => e
      raise Error, "could not retitle ##{number}: #{e.message.lines.first.to_s.strip}"
    end

    # @return [Boolean] whether `gh` is installed and authenticated
    def available?
      @command.run!("gh", "auth", "status").success?
    end
  end
end
