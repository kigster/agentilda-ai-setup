# frozen_string_literal: true

RSpec.describe SpecPlanBuild::StateMachine do
  # A stand-in for a folder: which files exist, which pull requests it records,
  # and where it was renamed to. The machine asks nothing else of a subject.
  let(:pr_class) { Struct.new(:state) { def open? = state.match?(/open|wip|draft/i) } }

  let(:subject_class) do
    Struct.new(:status, :files, :pull_requests, :renames) do
      def file?(name) = files.key?(name)

      def read(name) = files[name]

      def rename_to(status) = renames << status.key
    end
  end

  def folder(key, files: {}, prs: [])
    subject_class.new(SpecPlanBuild::STATUS_BY_KEY.fetch(key), files, prs.map { |s| pr_class.new(s) }, [])
  end

  def machine_for(...) = described_class.new(folder(...))

  # A folder far enough along to have pull requests at all.
  def built(key, prs:, files: {})
    folder(key, files: {"spec.md" => "x", "plan.md" => "y", "pull-requests.md" => "z"}.merge(files), prs:)
  end

  describe "the derived topology" do
    it "reads inbound and outbound off the same declarations, so they cannot disagree" do
      described_class.inbound.each do |to, froms|
        froms.each do |from|
          expect(described_class.outbound(from)).to include(to),
            "expected #{from} -> #{to} to be reachable in both directions"
        end
      end
    end

    it "gives every state exactly one event that reaches it" do
      reachable = SpecPlanBuild::STATUSES.map(&:key) - [:retroactive]

      expect(described_class.event_for.keys).to match_array(reachable)
    end

    it "gives retroactive no inbound edge, because it is a birth state" do
      expect(described_class.inbound).not_to have_key(:retroactive)
    end

    it "makes discarded the only terminal state and strands nothing else" do
      terminal = SpecPlanBuild::STATUSES.select(&:terminal?).map(&:key)

      expect(terminal).to eq([:discarded])
    end

    it "lets a release be pulled back out of production" do
      aggregate_failures do
        expect(described_class.edge?(:deployed, :rolled_back)).to be(true)
        expect(described_class.edge?(:rolled_back, :ready_for_review)).to be(true)
        expect(described_class.edge?(:rolled_back, :building)).to be(true)
      end
    end

    it "lets anything be discarded, from anywhere" do
      others = SpecPlanBuild::STATUSES.map(&:key) - [:discarded]

      expect(described_class.inbound.fetch(:discarded)).to match_array(others)
    end
  end

  describe "invariants" do
    it "requires the file that proves each phase happened" do
      aggregate_failures do
        expect(SpecPlanBuild::STATUS_BY_KEY[:new].satisfied_by?(folder(:new))).to be(false)
        expect(SpecPlanBuild::STATUS_BY_KEY[:new]
          .satisfied_by?(folder(:new, files: {"spec.md" => "x"}))).to be(true)
        expect(SpecPlanBuild::STATUS_BY_KEY[:planned]
          .satisfied_by?(folder(:planned, files: {"spec.md" => "x"}))).to be(false)
        expect(SpecPlanBuild::STATUS_BY_KEY[:planned]
          .satisfied_by?(folder(:planned, files: {"spec.md" => "x", "plan.md" => "y"}))).to be(true)
      end
    end

    it "refuses Approved while a pull request is still open, and says how many" do
      subject = built(:approved, prs: ["Open 🟡", "Merged 🟣"])

      expect(SpecPlanBuild::STATUS_BY_KEY[:approved].violation(subject))
        .to eq("Approved & Merged, but 1 pull request still open")
    end

    it "accepts Approved once every pull request is merged" do
      expect(SpecPlanBuild::STATUS_BY_KEY[:approved]).to be_satisfied_by(built(:approved, prs: ["Merged 🟣"]))
    end

    # 🟢 👀 🔴 all mean "open pull requests exist", and share one invariant so
    # the three cannot drift into disagreeing about what that means.
    it "requires an open pull request for every state in the review phase" do
      aggregate_failures do
        %i[ready_for_review in_review rejected].each do |key|
          status = SpecPlanBuild::STATUS_BY_KEY.fetch(key)

          expect(status).to be_satisfied_by(built(key, prs: ["Open 🟡"]))
          expect(status.violation(built(key, prs: ["Merged 🟣"]))).to match(/already merged/)
        end
      end
    end

    it "insists a deferral names its trigger, so deferrals cannot rot quietly" do
      aggregate_failures do
        expect(SpecPlanBuild::STATUS_BY_KEY[:deferred]
          .satisfied_by?(folder(:deferred, files: {"delayed.md" => "not now"}))).to be(false)
        expect(SpecPlanBuild::STATUS_BY_KEY[:deferred]
          .satisfied_by?(folder(:deferred, files: {"delayed.md" => "revisit once 018 ships"}))).to be(true)
      end
    end

    it "stops a folder being Retroactive once it has been documented" do
      subject = folder(:retroactive, files: {"spec.md" => "written up"}, prs: ["Merged 🟣"])

      expect(SpecPlanBuild::STATUS_BY_KEY[:retroactive].violation(subject)).to match(/already exists/)
    end
  end

  describe "#allowed" do
    it "offers the next spine state once its guard is satisfied" do
      machine = machine_for(:new, files: {"spec.md" => "x", "plan.md" => "y"})

      expect(machine.allowed).to include(:planned)
    end

    it "withholds it while the guard fails" do
      machine = machine_for(:new, files: {"spec.md" => "x"})

      expect(machine.allowed).not_to include(:planned)
    end

    it "never offers a state the topology does not reach, however well its guard passes" do
      machine = described_class.new(built(:new, prs: ["Merged 🟣"]))

      expect(machine.allowed).not_to include(:approved)
    end
  end

  describe "#promote!" do
    it "walks the spine when given no destination, and renames the folder" do
      subject = folder(:new, files: {"spec.md" => "x", "plan.md" => "y"})

      expect(described_class.new(subject).promote!.key).to eq(:planned)
      expect(subject.renames).to eq([:planned])
    end

    it "moves to a named destination off the spine" do
      subject = folder(:new, files: {"spec.md" => "x", "blocked.md" => "B1"})

      expect(described_class.new(subject).promote!(:blocked).key).to eq(:blocked)
      expect(subject.renames).to eq([:blocked])
    end

    # A refusal is information: it says the phase has not actually happened.
    it "refuses with the destination's own violation when the guard fails" do
      subject = folder(:new, files: {"spec.md" => "x"})

      expect { described_class.new(subject).promote!(:planned) }
        .to raise_error(described_class::Refused, /Planned requires `plan.md`/)
      expect(subject.renames).to be_empty
    end

    it "refuses with the edge itself when the topology has no such move" do
      subject = built(:new, prs: ["Merged 🟣"])

      expect { described_class.new(subject).promote!(:approved) }
        .to raise_error(described_class::Refused, /New cannot become .*Approved & Merged/)
    end

    it "says so plainly at a terminal state" do
      expect { machine_for(:discarded, files: {"discarded.md" => "no"}).promote! }
        .to raise_error(described_class::Refused, /terminal/)
    end

    it "walks 🔴 back to 🟢 rather than skipping the reviewer" do
      subject = built(:rejected, prs: ["Open 🟡"])

      expect(described_class.new(subject).promote!.key).to eq(:ready_for_review)
    end

    it "sends a review that found slop to 💩, keeping the plan and dropping the work" do
      subject = built(:in_review, files: {"rewrite.md" => "start over"}, prs: ["Open 🟡"])

      expect(described_class.new(subject).promote!(:shit).key).to eq(:shit)
    end
  end

  describe "#spine_next" do
    it "walks spec → plan → build → review → merge → ship" do
      expected = {
        retroactive: :planned, new: :planned, planned: :building, building: :ready_for_review,
        ready_for_review: :in_review, in_review: :approved, approved: :deployed,
        rejected: :ready_for_review, rolled_back: :ready_for_review, shit: :planned,
        discarded: nil, blocked: nil, deployed: nil
      }

      aggregate_failures do
        expected.each { |from, to| expect(machine_for(from).spine_next).to eq(to), "#{from} -> #{to}" }
      end
    end
  end

  describe "#best_fit" do
    it "picks the furthest state along the spine that the contents justify" do
      machine = described_class.new(built(:retroactive, prs: ["Merged 🟣"]))

      expect(machine.best_fit.key).to eq(:approved)
    end

    it "settles on Planned when there are no pull requests yet" do
      machine = machine_for(:building, files: {"spec.md" => "x", "plan.md" => "y"})

      expect(machine.best_fit.key).to eq(:planned)
    end

    it "prefers a block over spine progress, because a block is the louder fact" do
      machine = machine_for(:building, files: {"spec.md" => "x", "plan.md" => "y", "blocked.md" => "B1"})

      expect(machine.best_fit.key).to eq(:blocked)
    end

    it "leaves a folder alone when its current status already holds" do
      machine = machine_for(:planned, files: {"spec.md" => "x", "plan.md" => "y"})

      expect(machine.best_fit.key).to eq(:planned)
    end

    # ⭕️ and 🅱️ share an invariant on purpose: both mean "a human must
    # decide", and only the folder name says which human. Nothing may re-derive
    # that from the contents, or every ⭕️ silently becomes 🅱️.
    it "never reclassifies between the two blocked states" do
      aggregate_failures do
        %i[blocked product_blocked].each do |key|
          expect(machine_for(key, files: {"blocked.md" => "B1. Who decides?"}).best_fit.key).to eq(key)
        end
      end
    end

    it "never reclassifies within the review phase, which disk contents cannot tell apart" do
      aggregate_failures do
        %i[building ready_for_review in_review rejected].each do |key|
          expect(described_class.new(built(key, prs: ["Open 🟡"])).best_fit.key).to eq(key)
        end
      end
    end

    # Arriving from outside the family, the contents prove only its floor.
    it "lands on the family's weakest member when a folder falls back into it" do
      machine = described_class.new(built(:approved, prs: ["Merged 🟣", "Open 🟡"]))

      expect(machine.best_fit.key).to eq(:building)
    end
  end

  describe "SpecPlanBuild.status" do
    it "resolves a state by its key and by its emoji" do
      aggregate_failures do
        expect(SpecPlanBuild.status(:building).label).to eq("Building")
        expect(SpecPlanBuild.status("⚪️").key).to eq(:new)
        expect(SpecPlanBuild.status("⚪").key).to eq(:new)
      end
    end

    # The synonym table that used to live here rotted: six of its words pointed
    # at a state that had been renamed out of existence.
    it "resolves nothing else, because a state has exactly two names" do
      aggregate_failures do
        %w[white star yellow green complete completed done wip ready aborted nonsense].each do |word|
          expect(SpecPlanBuild.status(word)).to be_nil, "expected #{word.inspect} not to resolve"
        end
      end
    end
  end
end
