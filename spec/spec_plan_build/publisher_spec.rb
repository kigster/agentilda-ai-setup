# frozen_string_literal: true

RSpec.describe SpecPlanBuild::Publisher, :tree do
  subject(:publisher) { described_class.new(root: File.dirname(plans_root), command:, dry_run: false) }

  let(:command) { instance_double(TTY::Command) }
  let(:result) { instance_double(TTY::Command::Result, out: "https://github.com/example/repo/pull/7\n") }

  let!(:built) do
    plans do |t|
      t.plan "000.00", :wip, "folder-capitalized-not-downcased",
        files: {"spec.md" => spec_body(goal: "Make the thing work.")}
    end
  end

  let(:plan) { SpecPlanBuild::Tree.new(dir: plans_root).subjects.first }
  # A Data instance is frozen, so dirtiness — the thing these examples vary —
  # cannot be stubbed on a real one.
  let(:checkout) do
    instance_double(SpecPlanBuild::Worktree::Checkout,
      branch: "kig/000.00-folder-capitalized-not-downcased",
      path: File.dirname(plans_root),
      dirty?: true)
  end

  before { allow(command).to receive(:run).and_return(result) }

  describe "#title_for" do
    it "matches the convention: [NNN.MM](A) with the folder title-cased" do
      expect(publisher.title_for(plan)).to eq("[000.00](A) Folder Capitalized Not Downcased")
    end

    it "continues the sequence for a plan that already has pull requests" do
      plans do |t|
        t.plan "001.00", :wip, "second-feature", prs: [t.merged(1, "first part")]
      end
      second = SpecPlanBuild::Tree.new(dir: plans_root).find("001.00")

      expect(publisher.title_for(second)).to start_with("[001.00](B)")
    end

    it "honours a forced letter" do
      expect(publisher.title_for(plan, "C")).to start_with("[000.00](C)")
    end

    # Every part is lettered, including the first: a plan that turns out to need
    # only one pull request still reads like every other, and nothing has to be
    # retitled when a second arrives.
    it "letters even a plan's only pull request" do
      expect(publisher.title_for(plan)).to include("(A)")
    end
  end

  describe "the title the rest of the system has to accept" do
    it "is recognised by resync prs as already prefixed, so it is never doubled" do
      expect(SpecPlanBuild::Resync::Prs::PREFIXED).to match(publisher.title_for(plan))
    end

    it "resolves back to the plan it came from" do
      match = /\[(\d{3}\.\d{2})\]/.match(publisher.title_for(plan))

      expect(SpecPlanBuild::Ordinal.parse(match[1])).to eq(plan.feature.ordinal)
    end
  end

  describe "#publish" do
    it "commits, pushes the branch, then opens the pull request" do
      publisher.publish(checkout:, subject: plan)

      aggregate_failures do
        expect(command).to have_received(:run).with("git", "add", "-A", hash_including(:chdir))
        expect(command).to have_received(:run)
          .with("git", "push", "-u", "origin", checkout.branch, hash_including(:chdir))
        expect(command).to have_received(:run)
          .with("gh", "pr", "create", "-a", "@me", "-B", "main", "-t",
            "[000.00](A) Folder Capitalized Not Downcased", "-F", anything, hash_including(:chdir))
      end
    end

    it "returns the URL gh printed" do
      expect(publisher.publish(checkout:, subject: plan).url)
        .to eq("https://github.com/example/repo/pull/7")
    end

    # The bracketed prefix is a join key for pull request titles. Repeating it
    # on every commit subject adds nothing and eats the 50 characters.
    it "keeps the prefix out of the commit subject" do
      publisher.publish(checkout:, subject: plan)

      expect(command).to have_received(:run)
        .with("git", "commit", "-m", "Folder Capitalized Not Downcased", hash_including(:chdir))
    end

    context "when the agent changed nothing" do
      let(:checkout) do
        instance_double(SpecPlanBuild::Worktree::Checkout,
          branch: "kig/000.00-x", path: File.dirname(plans_root), dirty?: false)
      end

      it "refuses rather than opening an empty pull request" do
        publication = publisher.publish(checkout:, subject: plan)

        aggregate_failures do
          expect(publication).not_to be_published
          expect(publication.refusal).to match(/unchanged/)
        end
      end

      it "runs no git or gh command at all" do
        publisher.publish(checkout:, subject: plan)

        expect(command).not_to have_received(:run)
      end
    end

    context "on a dry run" do
      subject(:publisher) do
        described_class.new(root: File.dirname(plans_root), command:, dry_run: true)
      end

      it "reports the title it would use and touches nothing" do
        publication = publisher.publish(checkout:, subject: plan)

        aggregate_failures do
          expect(publication.title).to eq("[000.00](A) Folder Capitalized Not Downcased")
          expect(publication).not_to be_published
          expect(command).not_to have_received(:run)
        end
      end
    end

    context "when gh refuses" do
      before do
        allow(command).to receive(:run).with("gh", any_args)
          .and_raise(TTY::Command::ExitError.new("gh pr create", instance_double(TTY::Command::Result,
            exit_status: 1, out: "", err: "a pull request already exists for this branch")))
      end

      it "reports the refusal instead of raising" do
        expect(publisher.publish(checkout:, subject: plan).refusal).to match(/already exists/)
      end
    end
  end
end
