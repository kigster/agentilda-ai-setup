# frozen_string_literal: true

RSpec.describe Agentilda::Runner, :tree do
  subject(:runner) { described_class.new(tree:, executor:, agents:, max_rounds: 5) }

  let(:tree) { Agentilda::Tree.new(dir: plans_root) }
  let(:agents) { Agentilda::Agents.new }

  # The executor is the seam. Nothing in the suite invokes `claude`, so the
  # loop's logic is tested without a model, a network or a bill.
  let(:executor) { ->(agent, subject, **) { record(agent, subject) } }
  let(:calls) { [] }

  # By default an agent does nothing, so the tree cannot change and the loop
  # must converge on that fact rather than spinning to the ceiling.
  def record(agent, subject)
    calls << [agent.name, subject.feature.ordinal.to_s]
    [true, "noop"]
  end

  describe "#call" do
    context "with plans in several states" do
      let!(:built) do
        plans do |t|
          t.plan "000.00", :new, "needs-a-spec", files: {"spec.md" => spec_body}
          t.plan "000.01", :researched, "needs-a-writer",
            files: {"spec.md" => "#{spec_body}\n## Research\n\nWhat was found.\n"}
          t.plan "001.00", :planned, "needs-a-plan", files: {"spec.md" => spec_body, "plan.md" => "# P"}
          t.plan "002.00", :blocked, "needs-a-human", files: {"blocked.md" => "B1. Which?"}
          t.plan "003.00", :approved, "finished", prs: [t.merged(3, "done")]
        end
      end

      # 001.00 already has spec.md and plan.md when the round starts, so
      # `palpatine-planner` takes it once — and Building no longer waits on a
      # pull request to exist, so the very next round finds it already there
      # and hands it straight to `luke-implementer`.
      it "offers each plan to the agent that handles its state" do
        runner.call

        expect(calls.uniq).to contain_exactly(["leah-researcher", "000.00"],
          ["yoda-writer", "000.01"], ["palpatine-planner", "001.00"], ["luke-implementer", "001.00"])
      end

      # The relay's whole point. Both used to declare `handles: [new]`, agents
      # are offered work in definition order and the runner takes the first,
      # so yoda-writer won on alphabetical order alone — and wrote goals and
      # conclusions over documents nobody had researched. They now hold
      # adjacent states rather than the same one.
      it "researches before it writes, rather than the two contending for ⚪️ New" do
        runner.call

        aggregate_failures do
          expect(calls).to include(["leah-researcher", "000.00"])
          expect(calls.filter_map { |name, ordinal| ordinal if name == "yoda-writer" }).to all(eq("000.01"))
        end
      end

      it "never offers a blocked plan to anyone — that is what blocked means" do
        runner.call

        expect(calls.map(&:last)).not_to include("002.00")
      end

      it "leaves finished plans alone" do
        runner.call

        expect(calls.map(&:last)).not_to include("003.00")
      end

      it "reports blocked plans so a human can see what is waiting on them" do
        runner.call

        expect(runner.blocked.map { |s| s.feature.ordinal.to_s }).to eq(["002.00"])
      end
    end

    describe "termination" do
      let!(:built) do
        plans { |t| t.plan "000.00", :new, "stuck", files: {"spec.md" => spec_body} }
      end

      it "stops after consecutive dry rounds rather than running to the ceiling" do
        runner.call

        expect(runner.rounds.size).to eq(described_class::DRY_ROUNDS)
      end

      it "never exceeds max_rounds even when every round changes something" do
        churn = described_class.new(tree:, agents:, max_rounds: 3, executor: lambda { |agent, subject, **|
          # Simulate real progress: write the file the next state requires.
          File.write(File.join(subject.feature.path, "plan.md"), "# P")
          record(agent, subject)
        })
        churn.call

        expect(churn.rounds.size).to be <= 3
      end

      it "stops immediately when nothing is actionable" do
        empty = described_class.new(
          tree: Agentilda::Tree.new(dir: plans_root), agents:, executor:
        )
        FileUtils.rm_rf(Dir.glob(File.join(plans_root, "*")))
        empty.call

        expect(empty.rounds.size).to eq(1)
      end
    end

    describe "progress is read from disk, not from what the agent claims" do
      let!(:built) do
        plans { |t| t.plan "000.00", :new, "advances", files: {"spec.md" => spec_body} }
      end

      it "records an advance only when the folder actually moved" do
        writer = described_class.new(tree:, agents:, max_rounds: 2, executor: lambda { |_a, subject, **|
          File.write(File.join(subject.feature.path, "plan.md"), "# P")
          [true, "wrote plan.md"]
        })
        writer.call

        expect(writer.rounds.first.attempts.first).to be_advanced
      end

      it "records no advance when the agent only says it succeeded" do
        liar = described_class.new(tree:, agents:, max_rounds: 2,
          executor: ->(_a, _s, **) { [true, "I totally did it"] })
        liar.call

        expect(liar.rounds.first.attempts.first).not_to be_advanced
      end
    end

    describe "#settled?" do
      it "is true when every plan is done or deliberately parked" do
        plans do |t|
          t.plan "000.00", :approved, "shipped", prs: [t.merged(1, "x")]
          t.plan "001.00", :blocked, "waiting", files: {"blocked.md" => "B1"}
        end

        expect(runner).to be_settled
      end

      it "is false while anything is still workable" do
        plans { |t| t.plan "000.00", :new, "todo", files: {"spec.md" => spec_body} }

        expect(runner).not_to be_settled
      end
    end

    # `--plan` is what makes a batch-create skill safe: it hands off exactly
    # the plans it just minted, not a whole-tree loop that a second and third
    # batch would each start again on top of.
    describe "--plan scoping" do
      subject(:runner) { described_class.new(tree:, executor:, agents:, max_rounds: 5, plans: [ordinal("000.00")]) }

      let!(:built) do
        plans do |t|
          t.plan "000.00", :new, "in-scope", files: {"spec.md" => spec_body}
          t.plan "001.00", :new, "out-of-scope", files: {"spec.md" => spec_body}
        end
      end

      def ordinal(text) = Agentilda::Ordinal.parse(text)

      it "only offers work to the plans named" do
        runner.call

        expect(calls.map(&:last).uniq).to eq(["000.00"])
      end

      it "leaves an out-of-scope plan's state exactly as it found it" do
        runner.call

        expect(tree.reload.find(ordinal("001.00")).status.key).to eq(:new)
      end

      describe "#in_scope?" do
        it "is true for a named plan" do
          expect(runner.in_scope?(tree.find(ordinal("000.00")))).to be(true)
        end

        it "is false for one left out" do
          expect(runner.in_scope?(tree.find(ordinal("001.00")))).to be(false)
        end
      end

      describe "#settled? and #blocked, scoped" do
        let!(:built) do
          plans do |t|
            t.plan "000.00", :approved, "in-scope", prs: [t.merged(1, "x")]
            t.plan "001.00", :new, "out-of-scope", files: {"spec.md" => spec_body}
          end
        end

        it "does not count an out-of-scope plan against #settled?" do
          expect(described_class.new(tree:, executor:, agents:, plans: [ordinal("000.00")])).to be_settled
        end

        it "does not report an out-of-scope block" do
          plans { |t| t.plan "002.00", :blocked, "out-of-scope-block", files: {"blocked.md" => "B1"} }

          expect(described_class.new(tree:, executor:, agents:, plans: [ordinal("000.00")]).blocked).to be_empty
        end
      end

      context "with no --plan given" do
        subject(:runner) { described_class.new(tree:, executor:, agents:, max_rounds: 5) }

        it "runs the whole tree, as before" do
          runner.call

          expect(calls.map(&:last).uniq).to contain_exactly("000.00", "001.00")
        end
      end
    end

    # `luke-implementer` decides when a plan is ready for review — a plan with
    # several work units is legitimately dirty long before the last one lands
    # — so it renames its own plan folder rather than leaving that guess to a
    # dirty checkout. This is the harness reacting to that rename, not causing
    # it. See `agents/luke-implementer.md`.
    describe "publishing once the agent renames its own folder to ready for review" do
      subject(:runner) do
        described_class.new(tree:, executor:, agents:, max_rounds: 1, isolation: :worktree, worktree:, publisher:)
      end

      let(:ordinal) { Agentilda::Ordinal.parse("004.00") }
      let(:checkout) do
        instance_double(Agentilda::Worktree::Checkout,
          branch: "kig/004.00-needs-a-reviewer", path: "/does-not-exist",
          plans_dir: "/does-not-exist/.plans", dirty?: true)
      end
      let(:worktree) { instance_double(Agentilda::Worktree, checkout_for: checkout) }
      let(:publication) do
        Agentilda::Publisher::Publication.new(
          ordinal:, branch: checkout.branch, title: "[004.00](A) Needs a Reviewer",
          url: "https://github.com/example/repo/pull/9", refusal: nil
        )
      end
      let(:publisher) { instance_double(Agentilda::Publisher, publish: publication) }

      # Stands in for `luke-implementer` finishing its last work unit: the
      # rename is the agent's own act, done before the harness ever asks
      # whether the checkout is dirty.
      let(:executor) do
        ->(_agent, subject, **) {
          subject.rename_to(Agentilda::STATUS_BY_KEY.fetch(:ready_for_review))
          [true, "completed"]
        }
      end

      let!(:built) do
        plans do |t|
          t.plan "004.00", :building, "needs-a-reviewer", files: {"spec.md" => spec_body, "plan.md" => "# P"}
        end
      end

      it "publishes and leaves the folder renamed, past the family resync would not touch on its own" do
        runner.call

        expect(tree.reload.find(ordinal).status.key).to eq(:ready_for_review)
      end

      it "records the opened pull request in the plan's own pull-requests.md" do
        runner.call

        prs = Agentilda::PullRequests.new(dir: tree.reload.find(ordinal).feature.path).all
        expect(prs.map(&:url)).to contain_exactly("https://github.com/example/repo/pull/9")
      end

      it "passes the freshly renamed subject the publisher needs to push and title the pull request" do
        runner.call

        expect(publisher).to have_received(:publish)
          .with(checkout:, subject: an_instance_of(Agentilda::Subject))
      end

      it "still honours the rename without a publisher, but opens no pull request — --dont-push-anything" do
        without_publisher = described_class.new(
          tree:, executor:, agents:, max_rounds: 1, isolation: :worktree, worktree:, publisher: nil
        )
        without_publisher.call

        found = tree.reload.find(ordinal)
        aggregate_failures do
          expect(found.status.key).to eq(:ready_for_review)
          expect(Agentilda::PullRequests.new(dir: found.feature.path).all).to be_empty
        end
      end

      it "never opens a pull request for a clean checkout — nothing left to push" do
        allow(checkout).to receive(:dirty?).and_return(false)
        runner.call

        expect(publisher).not_to have_received(:publish)
      end

      it "does not publish while the agent leaves the folder as Building — more units remain" do
        keeps_building = ->(_agent, _subject, **) { [true, "one of several units"] }
        mid_plan = described_class.new(
          tree:, executor: keeps_building, agents:, max_rounds: 1, isolation: :worktree, worktree:, publisher:
        )
        mid_plan.call

        aggregate_failures do
          expect(tree.reload.find(ordinal).status.key).to eq(:building)
          expect(publisher).not_to have_received(:publish)
        end
      end
    end
  end
end
