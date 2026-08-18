# frozen_string_literal: true

module SpecPlanBuild
  # `/spec-status` — every plan, its state in icon and words, and its pull
  # requests as clickable links.
  #
  # {#render} returns a string and prints nothing. Whoever calls it decides
  # where it goes, which keeps the table pipeable.
  class Reporter
    # Columns, so the header and the rows cannot drift apart.
    HEADINGS = ["Plan", "", "Status", "Feature", "Pull Requests"].freeze

    # @param tree [SpecPlanBuild::Tree]
    def initialize(tree:)
      @tree = tree
    end

    # @return [SpecPlanBuild::Tree]
    attr_reader :tree

    # @return [String] the whole table, newline-terminated
    def render
      return "No plans found in #{tree.dir}\n" if tree.subjects.empty?

      [header, *tree.subjects.flat_map { |s| rows_for(s) }, "", footer].join("\n") + "\n"
    end

    # @return [Hash{Symbol => Integer}] how many plans sit in each state
    def totals
      tree.subjects.each_with_object(Hash.new(0)) { |s, h| h[s.status.key] += 1 }
    end

    # Plans whose folder name their contents do not justify.
    #
    # @return [Array<SpecPlanBuild::Subject>]
    def inconsistent = tree.subjects.reject(&:consistent?)

    private

    # @return [Integer] widest status label, so the column lines up
    def label_width = @label_width ||= tree.subjects.map { |s| s.status.label.length }.max.to_i

    # @return [Integer] widest feature name
    def title_width = @title_width ||= tree.subjects.map { |s| s.feature.title.length }.max.to_i

    # @return [String]
    def header
      line = format("  %-7s %-2s  %-#{label_width}s  %-#{title_width}s  %s", *HEADINGS)
      [UI.paint(line, :bold), UI.paint("  " + "─" * (line.length - 2), :bright_black)].join("\n")
    end

    # One line per plan, plus a continuation line for each extra pull request
    # so that every URL is visible and clickable rather than truncated.
    #
    # @param subject [SpecPlanBuild::Subject]
    # @return [Array<String>]
    def rows_for(subject)
      feature = subject.feature
      prs = subject.pull_requests
      flag = subject.consistent? ? " " : UI.paint("!", :red)

      first = format("%s %-7s %-2s  %-#{label_width}s  %-#{title_width}s  %s",
        flag,
        UI.paint(feature.ordinal.to_s, :bold),
        feature.status.emoji,
        UI.paint(feature.status.label, :cyan),
        feature.title,
        prs.empty? ? UI.paint("—", :bright_black) : link(prs.first))

      rest = prs.drop(1).map do |pr|
        format("  %-7s %-2s  %-#{label_width}s  %-#{title_width}s  %s", "", "", "", "", link(pr))
      end

      [first, *rest, *violation_line(subject)]
    end

    # @param pr [SpecPlanBuild::PullRequest]
    # @return [String]
    def link(pr)
      "#{UI.paint("##{pr.number}", :bright_black)} #{pr.url} #{state_badge(pr)}"
    end

    # @param pr [SpecPlanBuild::PullRequest]
    # @return [String]
    def state_badge(pr)
      colour = if pr.merged? then :magenta
      elsif pr.open? then :yellow
      else :bright_black
      end
      UI.paint("(#{pr.state})", colour)
    end

    # @param subject [SpecPlanBuild::Subject]
    # @return [Array<String>]
    def violation_line(subject)
      return [] if subject.consistent?

      [format("  %-7s %-2s  %s", "", "", UI.paint("↳ #{subject.violation}", :red))]
    end

    # @return [String]
    def footer
      counts = totals.map { |key, n| "#{STATUS_BY_KEY.fetch(key).emoji} #{n}" }.join("   ")
      summary = "  #{tree.subjects.size} plans   #{counts}"
      lines = [summary]

      unless inconsistent.empty?
        lines << "  #{UI.paint("#{inconsistent.size} with a status their contents do not justify", :red)}"
      end

      tree.duplicates.each do |ordinal, dirnames|
        lines << "  #{UI.paint("#{ordinal} is claimed by #{dirnames.size} folders — a number is an identity:", :red)}"
        dirnames.each { |d| lines << "    #{UI.paint(d, :bright_black)}" }
      end

      lines.join("\n")
    end
  end
end
