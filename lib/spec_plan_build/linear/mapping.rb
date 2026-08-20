# frozen_string_literal: true

module SpecPlanBuild
  module Linear
    # What a folder's state means to Linear.
    #
    # Linear gives every workflow state a *type* — one of five, fixed across
    # every workspace — and a *name*, which each team chooses for itself. A
    # team may call its started state "In Progress", "Doing" or "🚧 WIP", so
    # matching on the name alone works right up until it meets somebody else's
    # workspace. Each row here therefore carries both: the type, which is the
    # contract, and the name we would prefer if the team happens to have one.
    # {Push} resolves the name first and falls back to the type.
    #
    # Four of the fifteen states have no Linear equivalent at all — a state
    # like ⭕️ Technical Block is a reason, not a position in a workflow — so
    # they map to the nearest position and carry a label saying which reason.
    #
    # @!attribute [r] type
    #   @return [String] Linear's canonical type: backlog, unstarted, started,
    #     completed or canceled
    # @!attribute [r] name
    #   @return [String] the state name to prefer when the team has one
    # @!attribute [r] labels
    #   @return [Array<String>] labels that carry what the type cannot
    Placement = Data.define(:type, :name, :labels)

    # Linear's five workflow state types, in lifecycle order.
    TYPES = %w[backlog unstarted started completed canceled].freeze

    # Every plan state, placed. Keyed by {SpecPlanBuild::Status#key}.
    #
    # This table must name every entry in {SpecPlanBuild::STATUSES}; a spec
    # asserts it does. That is the whole guard against the failure this file
    # is most prone to: a sixteenth state gets added, nothing here changes,
    # and its plans quietly import as Backlog with no indication anything was
    # missed.
    PLACEMENTS = {
      new: Placement.new(type: "backlog", name: "Backlog", labels: []),
      planned: Placement.new(type: "unstarted", name: "Todo", labels: []),
      building: Placement.new(type: "started", name: "In Progress", labels: []),
      ready_for_review: Placement.new(type: "started", name: "In Review", labels: []),
      in_review: Placement.new(type: "started", name: "In Review", labels: []),
      rejected: Placement.new(type: "started", name: "In Review", labels: %w[changes-requested]),
      approved: Placement.new(type: "completed", name: "Done", labels: []),
      deployed: Placement.new(type: "completed", name: "Done", labels: %w[deployed]),
      rolled_back: Placement.new(type: "started", name: "In Progress", labels: %w[rolled-back]),
      shit: Placement.new(type: "unstarted", name: "Todo", labels: %w[scrapped]),
      blocked: Placement.new(type: "unstarted", name: "Todo", labels: %w[blocked]),
      product_blocked: Placement.new(type: "unstarted", name: "Todo", labels: %w[blocked-on-product]),
      deferred: Placement.new(type: "backlog", name: "Backlog", labels: %w[deferred]),
      retroactive: Placement.new(type: "completed", name: "Done", labels: %w[retroactive]),
      discarded: Placement.new(type: "canceled", name: "Canceled", labels: [])
    }.freeze

    # Where a plan in this state belongs on a Linear board.
    #
    # @param status [SpecPlanBuild::Status]
    # @return [SpecPlanBuild::Linear::Placement]
    # @raise [SpecPlanBuild::Error] when the state has never been placed
    def self.placement(status)
      PLACEMENTS.fetch(status.key) do
        raise Error, "#{status} has no Linear placement — add one to Linear::PLACEMENTS"
      end
    end
  end
end
