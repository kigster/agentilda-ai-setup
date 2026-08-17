# frozen_string_literal: true

module SpecPlanBuild
  # A folder's state, and the rule that makes that state honest.
  #
  # `invariant` is the whole design. It answers "may this folder legitimately
  # BE in this state?", and it is used in both directions: `promote` asks it of
  # the destination before moving, `resync` and `check` ask it of the current
  # state to catch folders whose name has drifted from their contents. One
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
    def terminal? = Lifecycle::OUTBOUND.fetch(key, []).empty?

    # @return [String] emoji and words, as the tables print it
    def to_s = "#{emoji} #{label}"
  end

  # Variation selectors make ⚪️ and ⚪ different strings that mean the same
  # thing to a human. Compare with them removed.
  #
  # @param str [String, nil]
  # @return [String]
  def self.fold_emoji(str) = str.to_s.gsub(/[\u{FE0E}\u{FE0F}\u{200D}]/, "")

  # Every state a plan folder may be in, in lifecycle order. That order drives
  # the legend, the generated documentation and the `--to` help text.
  #
  # 🟣 Merged is deliberately absent: it is a pull request's status, not a
  # folder's, and giving it a folder state invites folders that claim a pull
  # request's condition as their own.
  STATUSES = [
    Status.new(
      key: :new, emoji: "⚪️", label: "New", requires: %w[spec.md],
      note: "a specification exists; it has not been planned yet",
      invariant: nil
    ),
    Status.new(
      key: :ready, emoji: "⭐️", label: "Ready", requires: %w[spec.md plan.md],
      note: "specified and planned; ready to be implemented",
      invariant: nil
    ),
    Status.new(
      key: :wip, emoji: "🟡", label: "In Progress", requires: %w[pull-requests.md],
      note: "at least one pull request raised, not all merged",
      invariant: ->(s) { "In Progress, but no pull requests are recorded" if s.pull_requests.empty? }
    ),
    Status.new(
      key: :done, emoji: "✅", label: "Done", requires: %w[pull-requests.md],
      note: "every pull request merged",
      invariant: lambda { |s|
        return "Done, but no pull requests are recorded" if s.pull_requests.empty?

        open = s.pull_requests.count(&:open?)
        "Done, but #{open} pull request#{"s" unless open == 1} still open" if open.positive?
      }
    ),
    Status.new(
      key: :blocked, emoji: "⭕️", label: "Blocked", requires: %w[blocked.md],
      note: "cannot proceed; an engineer or the CTO must decide something first",
      invariant: nil
    ),
    Status.new(
      key: :product_blocked, emoji: "🅱️", label: "Product Blocked", requires: %w[blocked.md],
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
      key: :retroactive, emoji: "⬜️", label: "Retroactive", requires: [],
      note: "the feature is live, but has neither a specification nor a plan",
      invariant: lambda { |s|
        next "Retroactive, but a `spec.md` already exists — it has been documented" if s.file?("spec.md")

        "Retroactive, but no pull requests are recorded" if s.pull_requests.empty?
      }
    ),
    Status.new(
      key: :rejected, emoji: "⛔️", label: "Rejected", requires: %w[rejected.md],
      note: "never going to be implemented; a terminal state",
      invariant: nil
    )
  ].freeze

  # Emoji => status, folded so ⚪ and ⚪️ both resolve.
  STATUS_BY_EMOJI = STATUSES.each_with_object({}) { |s, h| h[fold_emoji(s.emoji)] ||= s }.freeze

  # Symbol => status.
  STATUS_BY_KEY = STATUSES.to_h { |s| [s.key, s] }.freeze

  # Words a human might type for a state, mapped to its key. Accepts the emoji
  # itself, the key, and the obvious synonyms.
  STATUS_ALIASES = {
    "new" => :new, "spec" => :new, "white" => :new,
    "ready" => :ready, "planned" => :ready, "plan" => :ready, "star" => :ready,
    "wip" => :wip, "progress" => :wip, "in-progress" => :wip, "open" => :wip, "yellow" => :wip,
    "done" => :done, "complete" => :done, "completed" => :done, "green" => :done,
    "blocked" => :blocked, "eng-blocked" => :blocked,
    "product-blocked" => :product_blocked, "pm-blocked" => :product_blocked,
    "deferred" => :deferred, "delayed" => :deferred, "later" => :deferred,
    "retroactive" => :retroactive, "retro" => :retroactive, "undocumented" => :retroactive,
    "rejected" => :rejected, "declined" => :rejected, "aborted" => :rejected
  }.freeze

  # @param emoji [String, nil]
  # @return [SpecPlanBuild::Status, nil]
  def self.status_for_emoji(emoji) = STATUS_BY_EMOJI[fold_emoji(emoji)]

  # Resolve whatever the user typed — an emoji, a key, a synonym — to a status.
  #
  # @param text [String, Symbol, nil]
  # @return [SpecPlanBuild::Status, nil]
  def self.status(text)
    return nil if text.nil?
    return text if text.is_a?(Status)

    key = text.to_s.strip
    STATUS_BY_KEY[key.to_sym] ||
      status_for_emoji(key) ||
      STATUS_BY_KEY[STATUS_ALIASES[key.downcase]]
  end

  # The state machine's topology, and the only place transitions are declared.
  #
  # Guards are deliberately not written here: the guard for entering a state is
  # always that state's own invariant.
  module Lifecycle
    # Destination => the states that may legitimately reach it.
    #
    # `retroactive` has no inbound edge — it is a birth state, produced by
    # `create --after` for work that shipped undocumented. `rejected` has no
    # outbound edge, because a terminal state that can be left is just a state.
    INBOUND = {
      new: %i[retroactive blocked product_blocked deferred],
      ready: %i[new retroactive blocked product_blocked deferred],
      wip: %i[ready retroactive blocked product_blocked deferred done],
      done: %i[wip retroactive],
      blocked: %i[new ready wip],
      product_blocked: %i[new ready wip],
      deferred: %i[new ready wip blocked product_blocked],
      rejected: %i[new ready wip retroactive blocked product_blocked deferred]
    }.freeze

    # Source => destinations, derived so the two can never fall out of step.
    OUTBOUND = INBOUND
      .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(to, froms), h| froms.each { |f| h[f] << to } }
      .transform_values(&:freeze)
      .freeze

    # The forward path a bare `promote` walks. Everything off this spine —
    # blocking, deferring, rejecting — has to be named explicitly, which is the
    # entire reason for having a machine rather than a rename.
    SPINE = {retroactive: :ready, new: :ready, ready: :wip, wip: :done}.freeze

    module_function

    # Build a machine positioned at the subject's current state.
    #
    # The subject is passed as finite_machine's `target` and is never mutated:
    # our state lives in a directory name, not in the object.
    #
    # @param subject [#status]
    # @return [FiniteMachine::StateMachine]
    def machine_for(subject)
      FiniteMachine.new(subject, initial: subject.status.key) do
        INBOUND.each do |to, froms|
          event :"to_#{to}", from: froms, to: to,
            if: ->(s, *) { SpecPlanBuild::STATUS_BY_KEY[to].satisfied_by?(s) }
        end
      end
    end

    # States the subject may move to right now, guards applied.
    #
    # @param subject [#status]
    # @return [Array<Symbol>]
    def allowed_from(subject)
      machine = machine_for(subject)
      OUTBOUND.fetch(subject.status.key, []).select { |to| machine.can?(:"to_#{to}") }
    end

    # @param from [Symbol]
    # @param to [Symbol]
    # @return [Boolean] whether the topology permits this edge at all
    def edge?(from, to) = OUTBOUND.fetch(from, []).include?(to)

    # The next state along the spine, whether or not its guard passes.
    #
    # @param subject [#status]
    # @return [Symbol, nil]
    def spine_next(subject) = SPINE[subject.status.key]

    # Preference order when several states fit. Blocks outrank spine progress
    # because a block is the louder fact; retroactive is last because it is the
    # absence of documents rather than the presence of any.
    PREFERENCE = %i[rejected deferred blocked product_blocked done wip ready new retroactive].freeze

    # States that share an invariant and are told apart only by the folder
    # name. ⭕️ Blocked and 🅱️ Product Blocked both mean "a human must decide
    # before this can move"; which human is recorded nowhere but the emoji.
    #
    # Nothing may re-derive a family member from contents alone, or every ⭕️
    # silently becomes 🅱️ the first time anything resyncs.
    FAMILIES = [%i[blocked product_blocked]].freeze

    # @param key [Symbol]
    # @return [Array<Symbol>, nil] the family +key+ belongs to, if any
    def self.family_of(key) = FAMILIES.find { |f| f.include?(key) }

    # The state a folder's contents justify — the answer to "well, what should
    # it be, then?". This is what `resync dirs` renames toward.
    #
    # Invariants are *minimum* requirements, not exact matches: a ⚪️ folder
    # that has since grown a `plan.md` still satisfies ⚪️, and is nonetheless
    # ⭐️ now. So the furthest-justified state wins, and the caller compares it
    # against the current one to decide whether anything should move.
    #
    # The single exception is a family: within one, the current status always
    # wins, because the contents genuinely cannot distinguish its members.
    #
    # @param subject [#status]
    # @return [SpecPlanBuild::Status, nil] nil when nothing fits at all
    def best_fit(subject)
      fitting = SpecPlanBuild::STATUSES.select { |s| s.satisfied_by?(subject) }
      return nil if fitting.empty?

      best = PREFERENCE.filter_map { |k| fitting.find { |s| s.key == k } }.first || fitting.first
      family = family_of(subject.status.key)
      return subject.status if family&.include?(best.key)

      best
    end
  end
end
