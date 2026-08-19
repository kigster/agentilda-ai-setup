# frozen_string_literal: true

# Real git repositories in a temp dir. A worktree is a git feature, and a test
# that fakes git tests the fake.
RSpec.describe SpecPlanBuild::Worktree do
  subject(:worktrees) { described_class.new(root: repo, dir: worktree_dir, user: "tester") }

  around do |example|
    Dir.mktmpdir("spb-worktree") do |tmp|
      @repo = File.join(tmp, "project")
      @worktree_dir = File.join(tmp, "project.worktrees")
      FileUtils.mkdir_p(File.join(@repo, SpecPlanBuild::PLANS_DIR))
      system("git", "-C", @repo, "init", "-q", "--initial-branch=main", out: File::NULL, err: File::NULL)
      system("git", "-C", @repo, "config", "user.email", "alan.turing@manchester.edu")
      system("git", "-C", @repo, "config", "user.name", "Alan Turing")
      File.write(File.join(@repo, "README.md"), "# project\n")
      system("git", "-C", @repo, "add", "-A", out: File::NULL, err: File::NULL)
      system("git", "-C", @repo, "commit", "-qm", "initial", out: File::NULL, err: File::NULL)
      example.run
    end
  end

  let(:repo) { @repo }
  let(:worktree_dir) { @worktree_dir }

  let(:feature) do
    SpecPlanBuild::Feature.new(
      ordinal: SpecPlanBuild::Ordinal.parse("002.00"),
      status: SpecPlanBuild::STATUS_BY_KEY.fetch(:new),
      slug: "tenancy-households",
      dirname: "002.00-⚪️-tenancy-households",
      path: File.join(repo, SpecPlanBuild::PLANS_DIR, "002.00-⚪️-tenancy-households")
    )
  end

  describe "#branch_for" do
    # Not cosmetic: this is the first thing `resync prs` reads when deciding
    # which plan a pull request implements, so the number carries itself from
    # here to a merged PR with nobody having to remember it.
    it "puts the plan number in the branch name, where resync prs looks for it" do
      expect(worktrees.branch_for(feature)).to eq("tester/002.00-tenancy-households")
    end

    it "produces a branch the pull-request resolver can parse" do
      match = SpecPlanBuild::Resync::Prs::BRANCH_PATTERN.match(worktrees.branch_for(feature))

      expect(match && match[1]).to eq("002.00")
    end
  end

  describe "#checkout_for" do
    it "creates a real worktree on its own branch" do
      checkout = worktrees.checkout_for(feature)

      aggregate_failures do
        expect(checkout).to be_created
        expect(File.directory?(checkout.path)).to be(true)
        expect(`git -C #{checkout.path} rev-parse --abbrev-ref HEAD`.strip).to eq("tester/002.00-tenancy-households")
      end
    end

    it "reuses an existing checkout rather than failing on a second round" do
      worktrees.checkout_for(feature)

      expect(worktrees.checkout_for(feature)).not_to be_created
    end

    it "puts worktrees beside the repository, never inside it" do
      checkout = worktrees.checkout_for(feature)

      expect(checkout.path).not_to start_with("#{repo}/")
    end

    # The whole point: two agents on two plans share nothing.
    it "gives two plans genuinely separate checkouts" do
      other = feature.with(ordinal: SpecPlanBuild::Ordinal.parse("003.00"), slug: "ledger")
      first = worktrees.checkout_for(feature)
      second = worktrees.checkout_for(other)

      File.write(File.join(first.path, "scratch.txt"), "from agent one")

      aggregate_failures do
        expect(second.path).not_to eq(first.path)
        expect(File.exist?(File.join(second.path, "scratch.txt"))).to be(false)
      end
    end
  end

  describe "a worktree directory deleted by hand" do
    # git keeps the registration, marks it `prunable`, and then refuses to
    # create a new worktree at that path — reporting "already exists" about a
    # directory that does not. Anyone who has ever rm -rf'd a worktree hits it.
    it "is recreated rather than refused" do
      first = worktrees.checkout_for(feature)
      FileUtils.rm_rf(first.path)

      expect { worktrees.checkout_for(feature) }.not_to raise_error
    end

    it "comes back on the same branch" do
      FileUtils.rm_rf(worktrees.checkout_for(feature).path)
      again = worktrees.checkout_for(feature)

      expect(`git -C #{again.path} rev-parse --abbrev-ref HEAD`.strip)
        .to eq("tester/002.00-tenancy-households")
    end
  end

  describe "#prune" do
    it "removes checkouts an agent left untouched, since they are pure cost" do
      checkout = worktrees.checkout_for(feature)

      expect { worktrees.prune }.to change { File.directory?(checkout.path) }.from(true).to(false)
    end

    it "keeps a checkout that has changes — that is the output" do
      checkout = worktrees.checkout_for(feature)
      File.write(File.join(checkout.path, "spec.md"), "# written by an agent\n")
      worktrees.prune

      aggregate_failures do
        expect(File.directory?(checkout.path)).to be(true)
        expect(checkout).to be_dirty
      end
    end
  end
end
