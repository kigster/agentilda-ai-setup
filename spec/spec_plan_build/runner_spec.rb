# frozen_string_literal: true

RSpec.describe SpecPlanBuild::Runner, :tree do
  subject(:runner) { described_class.new(tree:, executor:, agents:, max_rounds: 5) }

  let(:tree) { SpecPlanBuild::Tree.new(dir: plans_root) }
  let(:agents) { SpecPlanBuild::Agents.new }

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

      it "offers each plan to the agent that handles its state" do
        runner.call

        expect(calls.uniq).to contain_exactly(["leah-researcher", "000.00"],
          ["yoda-writer", "000.01"], ["palpatine-planner", "001.00"])
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
          tree: SpecPlanBuild::Tree.new(dir: plans_root), agents:, executor:
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
  end
end
