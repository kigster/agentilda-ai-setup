# frozen_string_literal: true

module SpecPlanBuild
  # Drives specialist agents over a `.plans` tree until it stops changing.
  #
  # The hard part of any agent loop is knowing when to stop, and this one does
  # not have to guess: the state machine already defines "satisfied". A round
  # advances plans; the loop ends at a FIXED POINT — a round in which no plan
  # changed state — or when nothing is left that an agent may touch.
  #
  # Blocked plans are not failures and not work. ⭕️ and 🅱️ mean a human must
  # decide, so the loop reports them and steps around them. An agent that could
  # move them would make the states meaningless.
  class Runner
    # What one agent did to one plan.
    #
    # @!attribute [r] ordinal
    #   @return [String]
    # @!attribute [r] agent
    #   @return [String]
    # @!attribute [r] from
    #   @return [Symbol] state before
    # @!attribute [r] to
    #   @return [Symbol] state after
    # @!attribute [r] ok
    #   @return [Boolean]
    # @!attribute [r] note
    #   @return [String]
    Attempt = Data.define(:ordinal, :agent, :from, :to, :ok, :note) do
      # @return [Boolean] whether the plan actually moved
      def advanced? = ok && from != to
    end

    # One pass over the tree.
    #
    # @!attribute [r] number
    #   @return [Integer] 1-based
    # @!attribute [r] attempts
    #   @return [Array<SpecPlanBuild::Runner::Attempt>]
    Round = Data.define(:number, :attempts) do
      # @return [Integer]
      def advanced = attempts.count(&:advanced?)

      # @return [Boolean] nothing moved, so another identical round is pointless
      def dry? = advanced.zero?
    end

    # One unit of work: an agent, a plan, and the checkout it happens in.
    #
    # @!attribute [r] agent
    #   @return [SpecPlanBuild::Agent]
    # @!attribute [r] subject
    #   @return [SpecPlanBuild::Subject]
    # @!attribute [r] root
    #   @return [String] the tree this agent sees
    # @!attribute [r] checkout
    #   @return [SpecPlanBuild::Worktree::Checkout, nil] nil when sharing a tree
    Task = Data.define(:agent, :subject, :root, :checkout) do
      # @return [String] for the spinner line
      def label = "#{subject.feature.ordinal}  #{agent.name}"

      # @return [String] where this task's plans live
      def plans_dir = checkout ? checkout.plans_dir : File.join(root, SpecPlanBuild::PLANS_DIR)
    end

    # Rounds with no movement before the loop concedes. One is not enough: an
    # agent can legitimately spend a round writing something another agent needs
    # before either can advance.
    DRY_ROUNDS = 2

    # @param tree [SpecPlanBuild::Tree]
    # @param executor [#call] receives (agent, subject) and returns [ok, note]
    # @param agents [SpecPlanBuild::Agents]
    # @param max_rounds [Integer] a hard ceiling, so a loop cannot run forever
    # @param isolation [Symbol] `:worktree` gives each plan its own checkout
    #   and branch; `:shared` runs every agent against one tree, which is only
    #   safe serially
    # @param jobs [Integer] how many agents run at once
    def initialize(tree:, executor:, agents: Agents.new, max_rounds: 10,
      isolation: :shared, jobs: 1, worktree: nil)
      @tree = tree
      @executor = executor
      @agents = agents
      @max_rounds = max_rounds
      @isolation = isolation
      @worktree = worktree
      @rounds = []

      # Concurrency without isolation is the exact failure the worktree exists
      # to prevent: two agents editing one checkout produce no git conflict, so
      # the last writer wins silently. Refuse rather than corrupt.
      @jobs = isolated? ? jobs : 1
    end

    # @return [Boolean]
    def isolated? = @isolation == :worktree

    # @return [Integer] agents running at once
    attr_reader :jobs

    # @return [SpecPlanBuild::Worktree, nil]
    attr_reader :worktree

    # @return [SpecPlanBuild::Tree]
    attr_reader :tree

    # @return [Array<SpecPlanBuild::Runner::Round>]
    attr_reader :rounds

    # Run until the tree stops changing.
    #
    # @return [Array<SpecPlanBuild::Runner::Round>]
    def call
      dry = 0

      1.upto(@max_rounds) do |number|
        round = run_round(number)
        @rounds << round
        break if round.attempts.empty?

        dry = round.dry? ? dry + 1 : 0
        break if dry >= DRY_ROUNDS
      end

      @rounds
    end

    # Plans nobody may act on, for the closing report.
    #
    # @return [Array<SpecPlanBuild::Subject>]
    def blocked = tree.subjects.select { |s| %i[blocked product_blocked].include?(s.status.key) }

    # @return [Boolean] every plan is either finished or deliberately parked
    def settled?
      tree.subjects.all? { |s| StateMachine::SETTLED.include?(s.status.key) }
    end

    private

    # @param number [Integer]
    # @return [SpecPlanBuild::Runner::Round]
    def run_round(number)
      tree.reload
      tasks = assignments.map { |agent, subject| prepare(agent, subject) }
      return Round.new(number:, attempts: []) if tasks.empty?

      results = UI.concurrently(tasks, "round #{number} — #{tasks.size} plans", jobs:, label: :label.to_proc) do |task|
        attempt(task)
      end

      Round.new(number:, attempts: results.map { |r| r.is_a?(Attempt) ? r : failed(r) })
    end

    # Give the task somewhere to work. Under isolation that is a fresh git
    # worktree on its own branch named `<user>/NNN.MM-slug` — which is also
    # what `resync prs` reads first, so the plan number carries itself all the
    # way to a merged pull request.
    #
    # @param agent [SpecPlanBuild::Agent]
    # @param subject [SpecPlanBuild::Subject]
    # @return [SpecPlanBuild::Runner::Task]
    def prepare(agent, subject)
      return Task.new(agent:, subject:, root: shared_root, checkout: nil) unless isolated?

      checkout = worktree.checkout_for(subject.feature)
      Task.new(agent:, subject:, root: checkout.path, checkout:)
    end

    # @return [String]
    def shared_root = File.dirname(tree.dir)

    # @param error [Exception]
    # @return [SpecPlanBuild::Runner::Attempt]
    def failed(error)
      Attempt.new(ordinal: "?", agent: "?", from: :unknown, to: :unknown, ok: false,
        note: error.is_a?(Exception) ? error.message.lines.first.to_s.strip : error.to_s)
    end

    # Exactly one agent per plan per round — the first that handles its state.
    # Offering a plan to two agents in one round invites them to write the same
    # file from two directions.
    #
    # @return [Array<Array(SpecPlanBuild::Agent, SpecPlanBuild::Subject)>]
    def assignments
      tree.subjects.filter_map do |subject|
        next if StateMachine::SETTLED.include?(subject.status.key)

        agent = @agents.for_status(subject.status).first
        agent && [agent, subject]
      end
    end

    # @param task [SpecPlanBuild::Runner::Task]
    # @return [SpecPlanBuild::Runner::Attempt]
    def attempt(task)
      ordinal = task.subject.feature.ordinal.to_s
      from = task.subject.status.key

      ok, note = @executor.call(task.agent, task.subject, root: task.root)
      note = "#{note} (#{task.checkout.branch})" if task.checkout

      Attempt.new(ordinal:, agent: task.agent.name, from:, ok: !!ok, note: note.to_s,
        to: state_after(task))
    end

    # Re-read from disk rather than trusting what the agent claims. The folder
    # name is the state, and only `resync dirs` is allowed to change it — so an
    # agent that says "done" but wrote nothing shows up as not having moved.
    #
    # @param task [SpecPlanBuild::Runner::Task]
    # @return [Symbol]
    def state_after(task)
      workspace = Tree.new(dir: task.plans_dir)
      return task.subject.status.key unless workspace.exist?

      Resync::Dirs.new(tree: workspace).call(commit: true)
      workspace.reload.find(task.subject.feature.ordinal)&.status&.key || task.subject.status.key
    end
  end
end
