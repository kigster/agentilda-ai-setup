# frozen_string_literal: true

module Agentilda
  # One row of a plan's `pull-requests.md`.
  #
  # @!attribute [r] number
  #   @return [String, nil] as written, without the `#`
  # @!attribute [r] title
  #   @return [String]
  # @!attribute [r] url
  #   @return [String, nil]
  # @!attribute [r] state
  #   @return [String] normalised words plus emoji, e.g. "Open 🟡"
  PullRequest = Data.define(:number, :title, :url, :state) do
    # Still awaiting a decision. A closed-unmerged pull request is finished
    # business, so it is neither open nor merged.
    #
    # @return [Boolean]
    def open? = state.match?(/\b(?:open|wip|draft)\b/i)

    # @return [Boolean]
    def merged? = state.match?(/\bmerged\b/i) && !state.match?(/\bunmerged\b/i)

    # @return [String] "#92 — Send mail through Resend"
    def label = number ? "##{number} — #{title}" : title
  end

  # Extracts the pull request roll-up from a plan folder.
  class PullRequests
    # A markdown link whose text may contain escaped brackets, because every
    # title this tool writes now opens with `\[NNN.MM\]`. Matching `[^\]]+`
    # stops at the escaped `]` and loses the URL with it.
    LINK = /\[((?:\\.|[^\]\\])+)\]\((https?:[^)\s]+)\)/

    # Canonical wording for the states we recognise, most specific first.
    STATES = [
      [/\bclosed\b|\bunmerged\b|\babandoned\b/i, "Closed 🔴"],
      [/\bmerged\b/i, "Merged 🟣"],
      [/\bdraft\b|\bwip\b/i, "WIP 🟡"],
      [/\bopen\b/i, "Open 🟡"]
    ].freeze

    # Filenames that may hold the table.
    CANDIDATES = %w[pull-requests.md pull_requests.md prs.md].freeze

    # The file this class writes, and the first one it looks for.
    FILENAME = CANDIDATES.first

    # Render `pull-requests.md` for a set of pull requests fetched from GitHub.
    #
    # The table is what {#parse} reads back and what the state machine judges
    # a folder by. The descriptions below it are for a reader — human or
    # agent — synthesizing a specification from work that already shipped:
    # the table says *which* pull requests, the bodies say *what they did*,
    # and a retroactive `spec.md` cannot be written from numbers alone.
    #
    # Prose after the table is ignored by the parser, so the two can coexist
    # in one file rather than needing a scratch file the folder rules forbid.
    #
    # @param prs [Array<Hash>] `{number:, title:, url:, state:, body:}`
    # @return [String]
    def self.render(prs)
      rows = prs.map { |pr|
        "| #{pr[:number]} | [#{escape(pr[:title])}](#{pr[:url]}) | #{pr[:state]} |"
      }

      <<~MARKDOWN
        # Pull Requests

        | Pull Request Number | Pull Request Name | Status |
        | ------------------: | :---------------- | -----: |
        #{rows.join("\n")}

        ## What these pull requests did

        #{prs.map { |pr| describe(pr) }.join("\n")}
      MARKDOWN
    end

    # @param pr [Hash]
    # @return [String]
    def self.describe(pr)
      body = pr[:body].to_s.strip
      body = "_No description was written on the pull request._" if body.empty?

      <<~MARKDOWN
        ### ##{pr[:number]} — #{pr[:title]}

        #{pr[:url]}

        #{body}
      MARKDOWN
    end

    # Three characters have to survive a round trip through a table cell.
    #
    # A `|` ends the cell, and a title containing one is not unusual —
    # "fix: guard against a || b".
    #
    # `[` and `]` are newer and cost more. Every title this tool writes now
    # opens with a plan number, so the row reads `[[013.00] Ship it](url)` —
    # and a markdown link whose text starts with `[` does not parse. The
    # title came back with the URL glued to it and `url` came back nil, which
    # is not a cosmetic loss: it is every pull request link on the page, and
    # the attachment on every Linear issue.
    #
    # @param text [String]
    # @return [String]
    def self.escape(text)
      text.to_s.gsub(/([\[\]|])/) { "\\#{$1}" }.gsub(/\s+/, " ").strip
    end

    # @param dir [String] absolute path to the plan folder
    def initialize(dir:)
      @dir = dir
    end

    # @return [Array<Agentilda::PullRequest>] possibly empty
    def all = @all ||= parse

    private

    # @return [String]
    attr_reader :dir

    # @return [Array<Agentilda::PullRequest>]
    def parse
      path = CANDIDATES.map { |f| File.join(dir, f) }.find { |p| File.file?(p) }
      return [] unless path

      text = File.read(path, encoding: "UTF-8")
      table = pick_table(Markdown.tables(text))
      return scrape(text) unless table

      rows = table[:rows].filter_map { |cells| row_to_pr(cells, columns(table[:header])) }
      rows.empty? ? scrape(text) : rows
    end

    # @param tables [Array<Hash>]
    # @return [Hash, nil]
    def pick_table(tables)
      tables.find { |t|
        t[:header].any? { |h| h.match?(/pull\s*request|\bpr\b|\A#\z|\Anumber\z/i) } &&
          t[:rows].any? { |r| r.any? { |c| c.match?(%r{/(?:pull|merge_requests)/\d+}) } }
      } || tables.find { |t| t[:rows].any? { |r| r.any? { |c| c.match?(%r{/pull/\d+}) } } }
    end

    # @param header [Array<String>]
    # @return [Hash{Symbol => Integer, nil}]
    def columns(header)
      {
        number: header.index { |h| h.match?(/number|\A#\z|\Apr\z|\Apr\s*#/i) },
        title: header.index { |h| h.match?(/name|title|summary|description|scope/i) },
        state: header.index { |h| h.match?(/status|state/i) }
      }
    end

    # @param cells [Array<String>]
    # @param idx [Hash{Symbol => Integer, nil}]
    # @return [Agentilda::PullRequest, nil]
    def row_to_pr(cells, idx)
      title_cell = cells[idx[:title] || 1].to_s

      # The title comes from the title column and the URL from wherever it is.
      # Scanning every cell for the first link and taking both from it reads
      # `| [#24](…) | Split verified into signed_off |` as an issue called
      # "#24", because the number column is a link too and comes first.
      titled = title_cell.match(LINK)
      link = titled || cells.filter_map { |c| c.match(LINK) }.first

      url = link && link[2]
      title = titled ? titled[1] : unformat(title_cell)
      title = title.gsub(/\\([\[\]|\\])/, '\1') # undo the escaping {.render} applies
      number = cells[idx[:number] || 0].to_s[/\d+/] || url&.[](%r{/(?:pull|merge_requests)/(\d+)}, 1)
      return nil if title.empty? && url.nil?

      PullRequest.new(number:, url:, title: title.empty? ? "Pull request" : title,
        state: normalize(cells[idx[:state] || -1].to_s))
    end

    # When there is no parsable table, scrape bare links so a folder that
    # plainly has pull requests does not report none.
    #
    # @param text [String]
    # @return [Array<Agentilda::PullRequest>]
    def scrape(text)
      text.scan(%r{https?://\S+?/(?:pull|merge_requests)/(\d+)}).flatten.uniq.map do |num|
        PullRequest.new(number: num, title: "Pull request ##{num}", state: "Unknown",
          url: text[%r{https?://\S+?/(?:pull|merge_requests)/#{num}\b}])
      end
    end

    # Strip the markdown a title was wrapped in without eating the title.
    #
    # An underscore between letters is not emphasis, it is an identifier —
    # `signed_off`, `as_of`, `pull_requests`. Removing every underscore turned
    # "Split verified into signed_off" into "signedoff" on the way to Linear.
    #
    # @param cell [String]
    # @return [String]
    def unformat(cell)
      cell.to_s.gsub(/[*`]/, "").sub(/\A_+/, "").sub(/_+\z/, "").strip
    end

    # @param cell [String]
    # @return [String]
    def normalize(cell)
      STATES.each { |pattern, label| return label if cell.match?(pattern) }
      stripped = cell.gsub(/[*_`]/, "").strip
      stripped.empty? ? "Unknown" : stripped
    end
  end
end
