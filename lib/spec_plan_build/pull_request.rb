# frozen_string_literal: true

module SpecPlanBuild
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
    # Canonical wording for the states we recognise, most specific first.
    STATES = [
      [/\bclosed\b|\bunmerged\b|\babandoned\b/i, "Closed 🔴"],
      [/\bmerged\b/i, "Merged 🟣"],
      [/\bdraft\b|\bwip\b/i, "WIP 🟡"],
      [/\bopen\b/i, "Open 🟡"]
    ].freeze

    # Filenames that may hold the table.
    CANDIDATES = %w[pull-requests.md pull_requests.md prs.md].freeze

    # @param dir [String] absolute path to the plan folder
    def initialize(dir:)
      @dir = dir
    end

    # @return [Array<SpecPlanBuild::PullRequest>] possibly empty
    def all = @all ||= parse

    private

    # @return [String]
    attr_reader :dir

    # @return [Array<SpecPlanBuild::PullRequest>]
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
    # @return [SpecPlanBuild::PullRequest, nil]
    def row_to_pr(cells, idx)
      title_cell = cells[idx[:title] || 1].to_s
      link_cell = cells.find { |c| c.match?(/\[[^\]]+\]\(https?:[^)]+\)/) } || title_cell
      link = link_cell.match(/\[([^\]]+)\]\((https?:[^)\s]+)\)/)

      url = link && link[2]
      title = link ? link[1] : title_cell.gsub(/[*_`]/, "").strip
      number = cells[idx[:number] || 0].to_s[/\d+/] || url&.[](%r{/(?:pull|merge_requests)/(\d+)}, 1)
      return nil if title.empty? && url.nil?

      PullRequest.new(number:, url:, title: title.empty? ? "Pull request" : title,
        state: normalize(cells[idx[:state] || -1].to_s))
    end

    # When there is no parsable table, scrape bare links so a folder that
    # plainly has pull requests does not report none.
    #
    # @param text [String]
    # @return [Array<SpecPlanBuild::PullRequest>]
    def scrape(text)
      text.scan(%r{https?://\S+?/(?:pull|merge_requests)/(\d+)}).flatten.uniq.map do |num|
        PullRequest.new(number: num, title: "Pull request ##{num}", state: "Unknown",
          url: text[%r{https?://\S+?/(?:pull|merge_requests)/#{num}\b}])
      end
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
