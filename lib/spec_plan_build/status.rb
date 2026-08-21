# frozen_string_literal: true

module SpecPlanBuild
  # A folder's state: what it means, which files it cannot be honest without,
  # and the rule that decides whether the folder may legitimately claim it.
  #
  # `invariant` is asked in both directions. {StateMachine} asks it of a
  # destination before moving there; `resync` and `check` ask it of the current
  # state, to catch folders whose name has drifted from their contents. One
  # definition, so the two can never disagree about what a state means.
  #
  # @!attribute [r] key
  #   @return [Symbol] machine-facing name, e.g. `:product_blocked`
  # @!attribute [r] emoji
  #   @return [String] as it appears in the folder name
  # @!attribute [r] label
  #   @return [String] the human words
  # @!attribute [r] requires
  #   @return [Array<String>] files this state cannot be honest without
  # @!attribute [r] note
  #   @return [String] one-line meaning, for tables and generated docs
  # @!attribute [r] invariant
  #   @return [Proc, nil] `(subject) -> String | nil` — the reason it does not hold
  Status = Data.define(:key, :emoji, :label, :requires, :note, :invariant) do
    # @param subject [#file?, #read, #pull_requests]
    # @return [Boolean]
    def satisfied_by?(subject) = violation(subject).nil?

    # @param subject [#file?, #read, #pull_requests]
    # @return [String, nil] why this state is not justified, nil when it is
    def violation(subject)
      missing = requires.reject { |f| subject.file?(f) }
      return "#{label} requires #{missing.map { |f| "`#{f}`" }.join(" and ")}" unless missing.empty?

      invariant&.call(subject)
    end

    # @return [Boolean] whether nothing may follow this state
    def terminal? = StateMachine.outbound(key).empty?

    # @return [String] emoji and words, as the tables print it
    def to_s = "#{emoji} #{label}"
  end

  # "1 pull request", "3 pull requests".
  #
  # @param count [Integer]
  # @return [String]
  def self.pull_request_count(count) = "#{count} pull request#{"s" unless count == 1}"

  # What proves a specification has been researched rather than merely
  # written: the chapter `leah-researcher` contributes. It is a section of
  # `spec.md` rather than a file of its own because research is not a separate
  # document — it is the first half of the specification, and splitting it
  # would leave `yoda-writer` reading two files to write one.
  RESEARCH_CHAPTER = /^[ \t]{0,3}\#{2,3}[ \t]+Research\b/i

  # Variation selectors make ⚪️ and ⚪ different strings that mean the same
  # thing to a human. Compare with them removed.
  #
  # @param str [String, nil]
  # @return [String]
  def self.fold_emoji(str) = str.to_s.gsub(/[\u{FE0E}\u{FE0F}\u{200D}]/, "")

  # 🟢 Ready for Review, 👀 In Review and 🔴 Changes Requested are the same
  # thing on disk — the work exists and at least one pull request is still
  # open. Which of the three it is lives in the folder name and nowhere else,
  # so they share one invariant rather than three that could drift apart.
  #
  # @param label [String]
  # @return [Proc]
  def self.open_pull_request(label)
    lambda { |subject|
      return "#{label} requires an open pull request; none are recorded" if subject.pull_requests.empty?

      "#{label}, but every pull request is already merged" if subject.pull_requests.none?(&:open?)
    }
  end

  # Every state a plan folder may be in, in lifecycle order. That order drives
  # the legend, the generated documentation and the `--to` help text.
  #
  # 🟣 Merged is deliberately absent: it is a pull request's status, not a
  # folder's, and giving it a folder state invites folders that claim a pull
  # request's condition as their own.
  #
  # Adding a state here, or changing an emoji, makes the hand-drawn
  # `docs/img/plan-spec-build.png` stale — `just docs` will show you, because
  # the mermaid source in the generated document moves with this list.
  STATUSES = [
    Status.new(
      key: :new, emoji: "⚪️", label: "New", requires: %w[spec.md],
      note: "a specification exists; it has not been planned yet",
      invariant: nil
    ),
    Status.new(
      key: :researched, emoji: "🔎", label: "Researched", requires: %w[spec.md],
      note: "the topic has been researched; `spec.md` carries a `## Research` chapter",
      invariant: lambda { |s|
        body = s.read("spec.md").to_s
        "Researched, but `spec.md` has no `## Research` chapter" unless body.match?(RESEARCH_CHAPTER)
      }
    ),
    Status.new(
      key: :planned, emoji: "⭐️", label: "Planned", requires: %w[spec.md plan.md],
      note: "specified and planned; nobody has started building",
      invariant: nil
    ),
    Status.new(
      key: :building, emoji: "🟡", label: "Building", requires: %w[spec.md plan.md pull-requests.md],
      note: "work is under way; pull requests are raised as each unit lands",
      invariant: ->(s) { "Building, but no pull requests are recorded" if s.pull_requests.empty? }
    ),
    Status.new(
      key: :ready_for_review, emoji: "🟢", label: "Ready for Review", requires: %w[spec.md plan.md pull-requests.md],
      note: "every pull request is green on CI and waiting for a reviewer",
      invariant: open_pull_request("Ready for Review")
    ),
    Status.new(
      key: :in_review, emoji: "👀", label: "In Review", requires: %w[spec.md plan.md pull-requests.md],
      note: "a reviewer has picked it up and has not ruled yet",
      invariant: open_pull_request("In Review")
    ),
    Status.new(
      key: :rejected, emoji: "🔴", label: "Changes Requested", requires: %w[spec.md plan.md pull-requests.md],
      note: "the review asked for fixes; resubmit once they are made",
      invariant: open_pull_request("Changes Requested")
    ),
    Status.new(
      key: :approved, emoji: "✅", label: "Approved & Merged", requires: %w[pull-requests.md],
      note: "reviewed, approved, and every pull request merged",
      invariant: lambda { |s|
        return "Approved & Merged, but no pull requests are recorded" if s.pull_requests.empty?

        open = s.pull_requests.count(&:open?)
        "Approved & Merged, but #{SpecPlanBuild.pull_request_count(open)} still open" if open.positive?
      }
    ),
    Status.new(
      key: :deployed, emoji: "😎", label: "Deployed", requires: %w[deployed.md],
      note: "live in production; `deployed.md` names the release, date and SHA",
      invariant: nil
    ),
    Status.new(
      key: :rolled_back, emoji: "😱", label: "Rolled Back", requires: %w[rollback.md],
      note: "it shipped and was pulled; `rollback.md` names what broke",
      invariant: nil
    ),
    Status.new(
      key: :shit, emoji: "💩", label: "Scrapped by Review", requires: %w[rewrite.md],
      note: "the review scrapped the work; the plan survives, the pull requests do not",
      invariant: nil
    ),
    Status.new(
      key: :blocked, emoji: "⭕️", label: "Technical Block", requires: %w[blocked.md],
      note: "cannot proceed; an engineer or the CTO must decide something first",
      invariant: nil
    ),
    Status.new(
      key: :product_blocked, emoji: "🅱️", label: "Product Block", requires: %w[blocked.md],
      note: "cannot proceed; a product manager must decide something first",
      invariant: nil
    ),
    Status.new(
      key: :deferred, emoji: "☢️", label: "Deferred", requires: %w[delayed.md],
      note: "could proceed and chose not to yet; `delayed.md` must name the trigger",
      invariant: lambda { |s|
        body = s.read("delayed.md").to_s
        "Deferred, but `delayed.md` names no trigger" unless body.match?(/trigger|revisit|when\b|until\b|once\b/i)
      }
    ),
    Status.new(
      key: :retroactive, emoji: "🕰️", label: "Retroactive", requires: [],
      note: "the feature is live, but has neither a specification nor a plan",
      invariant: lambda { |s|
        next "Retroactive, but a `spec.md` already exists — it has been documented" if s.file?("spec.md")

        "Retroactive, but no pull requests are recorded" if s.pull_requests.empty?
      }
    ),
    Status.new(
      key: :discarded, emoji: "❌", label: "Discarded", requires: %w[discarded.md],
      note: "dropped for good; `discarded.md` says why. A terminal state",
      invariant: nil
    )
  ].freeze

  # Emoji => status, folded so ⚪ and ⚪️ both resolve.
  STATUS_BY_EMOJI = STATUSES.each_with_object({}) { |s, h| h[fold_emoji(s.emoji)] ||= s }.freeze

  # Symbol => status.
  STATUS_BY_KEY = STATUSES.to_h { |s| [s.key, s] }.freeze

  # @param emoji [String, nil]
  # @return [SpecPlanBuild::Status, nil]
  def self.status_for_emoji(emoji) = STATUS_BY_EMOJI[fold_emoji(emoji)]

  # Resolve a state from the only two names it has: its key, and its emoji.
  #
  # There is deliberately no synonym table. A state that also answers to
  # "star", "green" and "completed" has four names to keep in step with the
  # folder, the generated docs and the agent frontmatter — and the synonym
  # table that used to live here went stale pointing six words at a state that
  # no longer existed.
  #
  # @param text [String, Symbol, SpecPlanBuild::Status, nil]
  # @return [SpecPlanBuild::Status, nil]
  def self.status(text)
    return nil if text.nil?
    return text if text.is_a?(Status)

    key = text.to_s.strip
    STATUS_BY_KEY[key.to_sym] || status_for_emoji(key)
  end
end
