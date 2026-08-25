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

  # `git worktree add` brings tracked files and nothing else, so an agent handed
  # a bare checkout cannot run the suite it was told to keep green. It then
  # reports a broken checkout as a broken plan, which is the expensive failure:
  # the diagnosis points at the code rather than at the tree.
  describe "seeding the files git ignores" do
    before do
      File.write(File.join(repo, ".gitignore"), ".env\nconfig/credentials/*.key\n")
      system("git", "-C", repo, "add", "-A", out: File::NULL, err: File::NULL)
      system("git", "-C", repo, "commit", "-qm", "ignore rules", out: File::NULL, err: File::NULL)

      File.write(File.join(repo, ".env"), "SECRET=from-main\n")
      FileUtils.mkdir_p(File.join(repo, "config", "credentials"))
      File.write(File.join(repo, "config", "credentials", "test.key"), "testkey\n")
    end

    it "gives a new checkout the .env git would not" do
      checkout = worktrees.checkout_for(feature)

      expect(File.read(File.join(checkout.path, ".env"))).to eq("SECRET=from-main\n")
    end

    it "gives it the credential key, which is what MissingKeyError is about" do
      checkout = worktrees.checkout_for(feature)

      expect(File.read(File.join(checkout.path, "config/credentials/test.key"))).to eq("testkey\n")
    end

    # Worktrees made before any of this existed are still out there, and the
    # seeder only ever adds a missing file, so repairing them costs one
    # subprocess and no risk.
    it "repairs a checkout that was created before seeding existed" do
      checkout = worktrees.checkout_for(feature)
      FileUtils.rm_f(File.join(checkout.path, ".env"))

      worktrees.checkout_for(feature)

      expect(File.exist?(File.join(checkout.path, ".env"))).to be(true)
    end

    it "leaves an agent's own edit alone rather than restoring the original" do
      checkout = worktrees.checkout_for(feature)
      File.write(File.join(checkout.path, ".env"), "SECRET=edited-by-agent\n")

      worktrees.checkout_for(feature)

      expect(File.read(File.join(checkout.path, ".env"))).to eq("SECRET=edited-by-agent\n")
    end

    # A seeded .env is gitignored, so it must not read as agent output. If it
    # did, `prune` would keep every checkout forever and the loop would grow a
    # worktree per round with nothing in any of them.
    it "does not make an untouched checkout look dirty to prune" do
      checkout = worktrees.checkout_for(feature)

      expect { worktrees.prune }.to change { File.directory?(checkout.path) }.from(true).to(false)
    end
  end

  describe "#seed when the seeder is unavailable" do
    before { stub_const("SpecPlanBuild::Worktree::SEEDER", "/nonexistent/setup-worktree") }

    # A plan is not worth abandoning over a seeding step.
    it "does not raise, so one missing script cannot stop the loop" do
      expect { worktrees.checkout_for(feature) }.not_to raise_error
    end

    it "still produces the checkout" do
      expect(File.directory?(worktrees.checkout_for(feature).path)).to be(true)
    end

    it "says it could not seed, rather than failing quietly" do
      # spec_helper swaps $stderr for a StringIO suite-wide, so RSpec's
      # `output(...).to_stderr` never sees anything. Swap it here instead.
      captured = StringIO.new
      original = $stderr
      begin
        $stderr = captured
        worktrees.seed(repo)
      ensure
        $stderr = original
      end

      expect(captured.string).to include("missing")
    end

    it "answers false so a caller can tell seeding did not happen" do
      expect(worktrees.seed(repo)).to be(false)
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
