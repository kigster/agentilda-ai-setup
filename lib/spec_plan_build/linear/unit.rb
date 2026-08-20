# frozen_string_literal: true

module SpecPlanBuild
  module Linear
    # One unit of work inside a plan — the thing that becomes a Linear issue.
    #
    # @!attribute [r] key
    #   @return [String] "PR-1", or {Units::WHOLE} for an undivided plan
    # @!attribute [r] title
    #   @return [String] the heading's words, without the "PR-1 —" part
    # @!attribute [r] body
    #   @return [String] everything under the heading, as written
    # @!attribute [r] pull_requests
    #   @return [Array<SpecPlanBuild::PullRequest>] the ones this unit claims
    Unit = Data.define(:key, :title, :body, :pull_requests) do
      # @return [Boolean] whether this stands for the plan as a whole
      def whole? = key == Units::WHOLE
    end

    # Reads the work units out of a plan folder.
    #
    # `plan.md` is written by an agent for humans, not as a data file, so this
    # reads the one structure the format has always had: a heading per unit,
    # naming the pull request it will become. Everything else is prose about
    # those units.
    #
    # Two things about real plans make that harder than it sounds, and both
    # were found by running this over thirty-eight of them:
    #
    #   * The unit headings are all at one level, but *which* level varies by
    #     document — `## PR-1 — …` in one plan, `### PR 020.01 — …` in the
    #     next. Deeper headings underneath them (`### PR-1 tests`) name the
    #     same unit again. Matching every heading that mentions a pull request
    #     turned one plan's three units into nine.
    #   * A plan numbers its units either from one (`PR-1`) or from its own
    #     spec number (`PR 020.01`). The second form is the first form with
    #     the plan's number glued on, so it is normalised back.
    #
    # A plan with no such headings is not an error. Retroactive plans have no
    # `plan.md` at all, and a small plan is often one pull request with no
    # internal divisions — both import as a single issue standing for the
    # whole plan, which is the honest reading of a plan that never divided
    # itself.
    class Units
      # The key given to the unit that stands for an undivided plan.
      WHOLE = "PLAN"

      # `## 2. PR-1 — …`, `### PR 020.01 — …`, and the several other ways the
      # same heading gets typed. The hashes are escaped because an unescaped
      # `#{` in a regexp literal is interpolation.
      HEADING = /\A(\#{2,4})[ \t]+(?:\d+[.)][ \t]*)?PR[\s_-]?(\d+(?:\.\d+)?)\b[ \t]*(.*)\z/i

      # A fenced block can hold anything, including lines that read as
      # headings — `plan.md` files are full of shell and SQL whose comments
      # start with `#`. Scanning without stripping fences invents units.
      FENCE = /^[ \t]{0,3}(?:```|~~~)/

      # `(✔ #38)`, `(▶︎ in-flight)`, `(⬜ blocked)` — a status glyph in a
      # trailing parenthetical. It is the state of the unit, which Linear
      # tracks itself, and leaving it in the title means every title churns
      # the moment the work moves.
      GLYPH_NOTE = /\s*\((?:[^\w\s(][^)]*)\)\s*\z/

      # Pull request numbers named in the heading: "(✔ #38)".
      NUMBERED = /#(\d+)\b/

      # @param subject [SpecPlanBuild::Subject]
      def initialize(subject:)
        @subject = subject
      end

      # @return [Array<SpecPlanBuild::Linear::Unit>] never empty
      def all = @all ||= divided.empty? ? [whole] : attach(divided)

      private

      # @return [SpecPlanBuild::Subject]
      attr_reader :subject

      # @return [Array<SpecPlanBuild::Linear::Unit>] possibly empty
      def divided = @divided ||= merge(sections).map { |key, title, body| Unit.new(key:, title:, body:, pull_requests: []) }

      # The plan as one unit, for a folder that never divided itself.
      #
      # @return [SpecPlanBuild::Linear::Unit]
      def whole
        Unit.new(key: WHOLE, title: subject.feature.title,
          body: subject.goal.join("\n\n"), pull_requests: subject.pull_requests)
      end

      # @return [Array<Array(String, String, String)>] key, title, body
      def sections
        lines = readable
        level = headings(lines).map(&:first).min
        return [] unless level

        found = []
        lines.each do |line|
          match = HEADING.match(line)
          if match && match[1].length == level
            found << [key_for(match[2]), clean(match[3]), +""]
          elsif found.any?
            found.last[2] << line << "\n"
          end
        end
        found.reject { |_, title, _| title.empty? }
      end

      # A heading at the shallowest level that names a pull request starts a
      # unit; a deeper one is that unit's contents.
      #
      # @param lines [Array<String>]
      # @return [Array<Array(Integer, String)>] level and key
      def headings(lines)
        lines.filter_map { |line|
          match = HEADING.match(line)
          [match[1].length, key_for(match[2])] if match
        }
      end

      # `PR 020.01` inside plan 020.00 is this plan's first unit, written the
      # long way. Reduced, so its key does not depend on which convention the
      # author reached for.
      #
      # @param number [String] "1" or "020.01"
      # @return [String]
      def key_for(number)
        major, minor = number.split(".")
        return "PR-#{number}" unless minor
        return "PR-#{number}" unless major.to_i == subject.feature.ordinal.major

        "PR-#{minor.to_i}"
      end

      # One unit, headed twice. Bodies join; the first title wins, because a
      # later heading for the same unit is a continuation and titles itself
      # like one — "PR-1 tests", "PR-1 parameters".
      #
      # @param sections [Array<Array(String, String, String)>]
      # @return [Array<Array(String, String, String)>]
      def merge(sections)
        sections.each_with_object({}) { |(key, title, body), by_key|
          if by_key.key?(key)
            by_key[key][2] = "#{by_key[key][2]}\n\n#{body}"
          else
            by_key[key] = [key, title, body]
          end
        }.values.map { |key, title, body| [key, title, body.strip] }
      end

      # Which pull requests each unit claims, by the three joins that exist
      # between `plan.md` and `pull-requests.md`, most explicit first.
      #
      # @param units [Array<SpecPlanBuild::Linear::Unit>]
      # @return [Array<SpecPlanBuild::Linear::Unit>]
      def attach(units)
        claimed = []
        found = units.map { |unit|
          prs = (numbered(unit) + named(unit)).uniq - claimed
          claimed.concat(prs)
          unit.with(pull_requests: prs)
        }

        return found unless found.one?

        # With one unit there is nowhere else for a pull request to go. That
        # is arithmetic rather than a guess, so it is done rather than warned
        # about — and it is the common case for the small plans.
        [found.first.with(pull_requests: subject.pull_requests)]
      end

      # The heading said so: `### PR 020.03 — Clerk webhooks (✔ #44)`.
      #
      # @param unit [SpecPlanBuild::Linear::Unit]
      # @return [Array<SpecPlanBuild::PullRequest>]
      def numbered(unit)
        wanted = heading_for(unit.key).to_s.scan(NUMBERED).flatten
        subject.pull_requests.select { |pr| wanted.include?(pr.number.to_s) }
      end

      # The pull request title said so: "Spec 010 PR-2: MAGI registry".
      #
      # @param unit [SpecPlanBuild::Linear::Unit]
      # @return [Array<SpecPlanBuild::PullRequest>]
      def named(unit)
        pattern = /\bPR[\s_-]?#{unit.key[/\d+\z/]}\b/i
        subject.pull_requests.select { |pr| pr.title.match?(pattern) }
      end

      # Every heading line that names a unit, grouped by its key — the deeper
      # continuation headings included, since any of them may be the one
      # carrying the pull request number.
      #
      # @return [Hash{String => Array<String>}]
      def headlines
        @headlines ||= readable.each_with_object(Hash.new { |h, k| h[k] = [] }) do |line, found|
          match = HEADING.match(line)
          found[key_for(match[2])] << line if match
        end
      end

      # @param key [String]
      # @return [String] every heading this unit was written under
      def heading_for(key) = headlines[key].join("\n")

      # Every line of `plan.md` that is not inside a fence, fence lines
      # themselves included in what gets dropped.
      #
      # @return [Array<String>]
      def readable
        @readable ||= begin
          fenced = false
          subject.read("plan.md").to_s.each_line(chomp: true).each_with_object([]) do |line, kept|
            if line.match?(FENCE)
              fenced = !fenced
            elsif !fenced
              kept << line
            end
          end
        end
      end

      # @param title [String]
      # @return [String]
      def clean(title)
        title.to_s
          .sub(/\A\([^)]*\)\s*/, "")     # "(010a) — Per-person taxes" — a nickname, not a title
          .sub(/\A[—–:.-]+\s*/, "")
          .sub(GLYPH_NOTE, "")
          .gsub(/[*_`]/, "")
          .strip
      end
    end
  end
end
