# frozen_string_literal: true

RSpec.describe SpecPlanBuild::Lifecycle do
  # A stand-in for a folder: which files exist, and which pull requests it
  # records. The invariants ask nothing else of a subject.
  let(:pr_class) { Struct.new(:state) { def open? = state.match?(/open|wip|draft/i) } }

  let(:subject_class) do
    Struct.new(:status, :files, :pull_requests) do
      def file?(name) = files.key?(name)

      def read(name) = files[name]
    end
  end

  def subject_for(key, files: {}, prs: [])
    subject_class.new(SpecPlanBuild::STATUS_BY_KEY.fetch(key), files, prs.map { |s| pr_class.new(s) })
  end

  describe "the derived topology" do
    it "derives OUTBOUND from INBOUND so the two can never disagree" do
      described_class::INBOUND.each do |to, froms|
        froms.each do |from|
          expect(described_class::OUTBOUND.fetch(from)).to include(to),
            "expected #{from} -> #{to} to be reachable in both directions"
        end
      end
    end

    it "makes rejected terminal and leaves no other state stranded" do
      aggregate_failures do
        expect(SpecPlanBuild::STATUS_BY_KEY[:rejected]).to be_terminal
        SpecPlanBuild::STATUSES.reject { |s| s.key == :rejected }.each do |status|
          expect(status).not_to be_terminal, "#{status.key} has no way out"
        end
      end
    end

    it "gives retroactive no inbound edge, because it is a birth state" do
      expect(described_class::INBOUND).not_to have_key(:retroactive)
    end
  end

  describe "invariants" do
    it "requires the file that proves each phase happened" do
      aggregate_failures do
        expect(SpecPlanBuild::STATUS_BY_KEY[:new].satisfied_by?(subject_for(:new))).to be(false)
        expect(SpecPlanBuild::STATUS_BY_KEY[:new]
          .satisfied_by?(subject_for(:new, files: {"spec.md" => "x"}))).to be(true)
        expect(SpecPlanBuild::STATUS_BY_KEY[:ready]
          .satisfied_by?(subject_for(:ready, files: {"spec.md" => "x"}))).to be(false)
        expect(SpecPlanBuild::STATUS_BY_KEY[:ready]
          .satisfied_by?(subject_for(:ready, files: {"spec.md" => "x", "plan.md" => "y"}))).to be(true)
      end
    end

    it "refuses Done while a pull request is still open, and says how many" do
      folder = subject_for(:done, files: {"pull-requests.md" => "x"}, prs: ["Open 🟡", "Merged 🟣"])

      expect(SpecPlanBuild::STATUS_BY_KEY[:done].violation(folder))
        .to eq("Done, but 1 pull request still open")
    end

    it "accepts Done once every pull request is merged" do
      folder = subject_for(:done, files: {"pull-requests.md" => "x"}, prs: ["Merged 🟣", "Merged 🟣"])

      expect(SpecPlanBuild::STATUS_BY_KEY[:done]).to be_satisfied_by(folder)
    end

    it "insists a deferral names its trigger, so deferrals cannot rot quietly" do
      aggregate_failures do
        expect(SpecPlanBuild::STATUS_BY_KEY[:deferred]
          .satisfied_by?(subject_for(:deferred, files: {"delayed.md" => "not now"}))).to be(false)
        expect(SpecPlanBuild::STATUS_BY_KEY[:deferred]
          .satisfied_by?(subject_for(:deferred, files: {"delayed.md" => "revisit once 018 ships"}))).to be(true)
      end
    end

    it "stops a folder being Retroactive once it has been documented" do
      folder = subject_for(:retroactive, files: {"spec.md" => "written up"}, prs: ["Merged 🟣"])

      expect(SpecPlanBuild::STATUS_BY_KEY[:retroactive].violation(folder)).to match(/already exists/)
    end
  end

  describe ".allowed_from" do
    it "offers the next spine state once its guard is satisfied" do
      folder = subject_for(:new, files: {"spec.md" => "x", "plan.md" => "y"})

      expect(described_class.allowed_from(folder)).to include(:ready)
    end

    it "withholds it while the guard fails" do
      folder = subject_for(:new, files: {"spec.md" => "x"})

      expect(described_class.allowed_from(folder)).not_to include(:ready)
    end

    it "never offers a state the topology does not reach, however well its guard passes" do
      folder = subject_for(:new, files: {"spec.md" => "x", "plan.md" => "y", "pull-requests.md" => "z"},
        prs: ["Merged 🟣"])

      expect(described_class.allowed_from(folder)).not_to include(:done)
    end

    it "leaves the subject frozen and unmutated — the state lives in the folder name" do
      folder = subject_for(:new, files: {"spec.md" => "x"}).freeze

      expect { described_class.allowed_from(folder) }.not_to raise_error
      expect(folder.status.key).to eq(:new)
    end
  end

  describe ".spine_next" do
    it "walks spec -> plan -> build and routes retroactive work back onto it" do
      aggregate_failures do
        expect(described_class.spine_next(subject_for(:new))).to eq(:ready)
        expect(described_class.spine_next(subject_for(:ready))).to eq(:wip)
        expect(described_class.spine_next(subject_for(:wip))).to eq(:done)
        expect(described_class.spine_next(subject_for(:retroactive))).to eq(:ready)
        expect(described_class.spine_next(subject_for(:rejected))).to be_nil
      end
    end
  end

  describe ".best_fit" do
    # A ⬜️ folder that has since been written up and shipped: its name is now
    # a lie, so resync has to choose, and Done is the furthest justified state.
    it "picks the furthest state along the spine that the contents justify" do
      folder = subject_for(:retroactive,
        files: {"spec.md" => "x", "plan.md" => "y", "pull-requests.md" => "z"},
        prs: ["Merged 🟣"])

      expect(described_class.best_fit(folder).key).to eq(:done)
    end

    it "settles on Ready when there are no pull requests yet" do
      folder = subject_for(:wip, files: {"spec.md" => "x", "plan.md" => "y"})

      expect(described_class.best_fit(folder).key).to eq(:ready)
    end

    it "prefers a block over spine progress, because a block is the louder fact" do
      folder = subject_for(:wip, files: {"spec.md" => "x", "plan.md" => "y", "blocked.md" => "B1"})

      expect(described_class.best_fit(folder).key).to eq(:blocked)
    end

    it "leaves a folder alone when its current status already holds" do
      folder = subject_for(:ready, files: {"spec.md" => "x", "plan.md" => "y"})

      expect(described_class.best_fit(folder).key).to eq(:ready)
    end

    # ⭕️ and 🅱️ share an invariant on purpose: both mean "a human must
    # decide", and only the folder name says which human. Nothing may re-derive
    # that from the contents, or every ⭕️ silently becomes 🅱️.
    it "never reclassifies between the two blocked states" do
      aggregate_failures do
        %i[blocked product_blocked].each do |key|
          folder = subject_for(key, files: {"blocked.md" => "B1. Who decides?"})
          expect(described_class.best_fit(folder).key).to eq(key)
        end
      end
    end
  end

  describe "SpecPlanBuild.status" do
    it "resolves keys, emoji and the words a human would actually type" do
      aggregate_failures do
        expect(SpecPlanBuild.status(:wip).label).to eq("In Progress")
        expect(SpecPlanBuild.status("⚪️").key).to eq(:new)
        expect(SpecPlanBuild.status("⚪").key).to eq(:new)
        expect(SpecPlanBuild.status("white").key).to eq(:new)
        expect(SpecPlanBuild.status("planned").key).to eq(:ready)
        expect(SpecPlanBuild.status("nonsense")).to be_nil
      end
    end
  end
end
