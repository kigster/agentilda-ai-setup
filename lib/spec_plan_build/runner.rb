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
    # @param plans [Array<SpecPlanBuild::Ordinal>, nil] restrict the loop to
    #   these plans; nil (the default) is the whole tree
    # @param publisher [SpecPlanBuild::Publisher, nil] pushes a finished
    #   worktree and opens its pull request as soon as one lands, rather than
    #   once at the very end of the whole loop. nil (the default) never
    #   pushes anything — the caller's opt-out.
    def initialize(tree:, executor:, agents: Agents.new, max_rounds: 10,
      isolation: :shared, jobs: 1, worktree: nil, plans: nil, publisher: nil)
      @tree = tree
      @executor = executor
      @agents = agents
      @max_rounds = max_rounds
      @isolation = isolation
      @worktree = worktree
      @plans = plans
      @publisher = publisher
      @rounds = []

      # Concurrency without isolation is the exact failure the worktree exists
      # to prevent: two agents editing one checkout produce no git conflict, so
      # the last writer wins silently. Refuse rather than corrupt.
      @jobs = isolated? ? jobs : 1
    end

    # @return [Boolean]
    def isolated? = @isolation == :worktree

    # @param subject [SpecPlanBuild::Subject]
    # @return [Boolean] whether this run's scope covers this plan at all —
    #   `--plan` restricts it; with no `--plan` every plan is in scope
    def in_scope?(subject) = @plans.nil? || @plans.include?(subject.feature.ordinal)

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
    def blocked = in_scope.select { |s| %i[blocked product_blocked].include?(s.status.key) }

    # @return [Boolean] every plan in scope is either finished or deliberately parked
    def settled?
      in_scope.all? { |s| StateMachine::SETTLED.include?(s.status.key) }
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

      # One serial pass over the *main* tree, run once per round rather than
      # once per task. `Executor#prompt_for` always names a plan folder by its
      # main-tree path — that is where `spec.md`/`plan.md`/a rename actually
      # land, under every isolation mode — and running `Resync::Dirs` from
      # `jobs` threads at once on the one tree they all share would be exactly
      # the hazard a worktree exists to prevent for code, just aimed at
      # `.plans` instead. Doing it here, after `UI.concurrently` has already
      # joined every thread, costs nothing: nobody is still writing.
      Resync::Dirs.new(tree:).call(commit: true)

      attempts = tasks.zip(results).map { |task, r| r.is_a?(Attempt) ? finish(task, r) : failed(r) }
      Round.new(number:, attempts:)
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

    # @return [Array<SpecPlanBuild::Subject>] the tree, or just the plans
    #   `--plan` named — computed fresh each call, since {#run_round} reloads
    #   {#tree} before reading it
    def in_scope = tree.subjects.select { |s| in_scope?(s) }

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
      in_scope.filter_map do |subject|
        next if StateMachine::SETTLED.include?(subject.status.key)

        agent = @agents.for_status(subject.status).first
        agent && [agent, subject]
      end
    end

    # Runs the agent and records what it claimed. `to` is left equal to
    # `from` here — deliberately unfinished — because whether the folder
    # actually moved cannot be answered yet: several of these run at once,
    # each in its own checkout, and the one tree that would prove it moved is
    # not safe to resync until every thread has stopped writing. {#finish}
    # settles it, once, after {#run_round}'s single serial resync.
    #
    # @param task [SpecPlanBuild::Runner::Task]
    # @return [SpecPlanBuild::Runner::Attempt]
    def attempt(task)
      ordinal = task.subject.feature.ordinal.to_s
      from = task.subject.status.key

      ok, note = @executor.call(task.agent, task.subject, root: task.root)
      note = "#{note} (#{task.checkout.branch})" if task.checkout

      Attempt.new(ordinal:, agent: task.agent.name, from:, ok: !!ok, note: note.to_s, to: from)
    end

    # Reads what {#run_round}'s resync just settled, rather than trusting
    # what the agent claims — an agent that says "done" but wrote nothing
    # shows up as not having moved. Publishing is the one further thing this
    # adds on top of that read.
    #
    # `resync` never moves a folder within a {StateMachine::FAMILIES} group on
    # its own — a `plan.md` and some pull requests look identical whether
    # nobody has looked yet or a reviewer just asked for changes, so guessing
    # between them would be a coin flip dressed up as a correction. Whether a
    # plan is ready to leave Building is `luke-implementer`'s call, not the
    # harness's: it renames the plan folder itself once there is no work unit
    # left in `plan.md` (see `agents/luke-implementer.md`), and the resync
    # above leaves that rename standing — "the current name always wins"
    # inside a family — even though nothing has opened a pull request yet.
    # This is what reacts to it: publish, so the invariant that rename is
    # jumping ahead of becomes true within the same round.
    #
    # @param task [SpecPlanBuild::Runner::Task]
    # @param attempt [SpecPlanBuild::Runner::Attempt]
    # @return [SpecPlanBuild::Runner::Attempt]
    def finish(task, attempt)
      return attempt unless attempt.ok

      current = tree.find(task.subject.feature.ordinal)
      to = current&.status&.key || attempt.from
      settled = Attempt.new(ordinal: attempt.ordinal, agent: attempt.agent, from: attempt.from,
        ok: attempt.ok, to:, note: attempt.note)
      return settled unless task.agent.advances_to == :ready_for_review && to == :ready_for_review

      publication = publish(task, current)
      note = if publication&.published?
        "#{settled.note}; opened #{publication.url}"
      elsif publication&.refusal
        "#{settled.note}; publish refused: #{publication.refusal}"
      else
        settled.note
      end

      Attempt.new(ordinal: settled.ordinal, agent: settled.agent, from: settled.from, ok: settled.ok, to:, note:)
    end

    # Push the finished branch and open its pull request, then record it in
    # the plan's own `pull-requests.md` — the file {Status::STATUS_BY_KEY}'s
    # `ready_for_review` invariant actually reads.
    #
    # `--isolation shared` has no branch of its own to push, so this is a
    # no-op there by construction rather than by a special case: {@publisher}
    # is nil unless the caller asked for pushing, and a shared task never has
    # a {Worktree::Checkout} to push in the first place.
    #
    # @param task [SpecPlanBuild::Runner::Task]
    # @param subject [SpecPlanBuild::Subject] read fresh, under its new name
    # @return [SpecPlanBuild::Publisher::Publication, nil]
    def publish(task, subject)
      return nil unless @publisher && task.checkout&.dirty?

      publication = @publisher.publish(checkout: task.checkout, subject:)
      record_pull_request(subject.feature.path, publication) if publication.published?
      publication
    end

    # @param path [String] the plan folder, in the main tree
    # @param publication [SpecPlanBuild::Publisher::Publication]
    # @return [void]
    def record_pull_request(path, publication)
      number = publication.url.to_s[%r{/pull/(\d+)}, 1]
      rows = PullRequests.new(dir: path).all.map { |pr|
        {number: pr.number, title: pr.title, url: pr.url, state: pr.state, body: ""}
      }
      rows << {number:, title: publication.title, url: publication.url, state: "Open 🟡", body: ""}
      File.write(File.join(path, PullRequests::FILENAME), PullRequests.render(rows))
    end
  end
end
