# frozen_string_literal: true

require "open3"
require "tmpdir"

# `bin/setup-worktree` is a standalone shell executable, so it is tested the way
# it is used: against throwaway git repositories with a real `git worktree add`
# behind them. The behaviour under test is entirely about the filesystem, and a
# mock of git would only prove that the mock agrees with itself.
RSpec.describe "bin/setup-worktree" do
  let(:script) { File.expand_path("../bin/setup-worktree", __dir__) }
  let(:root) { Dir.mktmpdir("setup-worktree") }
  let(:main) { File.join(root, "main") }
  let(:tree) { File.join(root, "tree") }

  after { FileUtils.remove_entry(root) if File.directory?(root) }

  def git(dir, *args)
    _out, err, status = Open3.capture3("git", "-C", dir, *args)
    raise "git #{args.first} failed: #{err}" unless status.success?
  end

  # @param path [String] repo-relative
  # @param body [String]
  # @return [void]
  def write(path, body, in_dir: main)
    full = File.join(in_dir, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end

  # A checkout holding one tracked file, one ignored .env, and the three
  # credential keys, then a worktree cut from it. This is the shape the script
  # exists for: `git worktree add` brings the tracked file and nothing else.
  #
  # @return [void]
  def seed
    FileUtils.mkdir_p(main)
    git(main, "init", "-q", "-b", "main")
    write(".gitignore", ".env\n.env.*\nconfig/credentials/*.key\nconfig/master.key\n")
    write("tracked.txt", "tracked\n")
    write(".env.example", "TRACKED_SAMPLE=1\n")
    git(main, "add", "-A")
    git(main, "-c", "user.email=alan.turing@manchester.edu", "-c", "user.name=Alan Turing", "-c", "commit.gpgsign=false",
      "commit", "-qm", "seed")

    write(".env", "SECRET=from-main\n")
    write("config/credentials/test.key", "testkey\n")
    write("config/credentials/production.key", "prodkey\n")
    File.chmod(0o600, File.join(main, "config/credentials/test.key"))

    git(main, "worktree", "add", "-q", tree, "-b", "side")
  end

  # @return [Array(String, Process::Status)] combined output and the status
  def run(*)
    out, err, status = Open3.capture3({"NO_COLOR" => "1"}, script, *)
    [out + err, status]
  end

  before { seed }

  describe "the files it brings across" do
    before { run(tree) }

    it "copies an ignored .env that the worktree did not get" do
      expect(File.read(File.join(tree, ".env"))).to eq("SECRET=from-main\n")
    end

    it "copies the test credential key" do
      expect(File.read(File.join(tree, "config/credentials/test.key"))).to eq("testkey\n")
    end

    it "keeps the key's mode rather than widening it to the default" do
      mode = File.stat(File.join(tree, "config/credentials/test.key")).mode & 0o777
      expect(mode).to eq(0o600)
    end

    # The safety property. Only ignored files are candidates, so the script can
    # add what a checkout was missing and can never shadow tracked content with
    # a stale copy carried over from somewhere else.
    it "leaves a tracked .env.example alone, matching name notwithstanding" do
      expect(File.read(File.join(tree, ".env.example"))).to eq("TRACKED_SAMPLE=1\n")
    end
  end

  describe "production keys" do
    it "skips the production key by default" do
      run(tree)
      expect(File).not_to exist(File.join(tree, "config/credentials/production.key"))
    end

    it "says out loud that it skipped it, rather than skipping silently" do
      out, = run(tree)
      expect(out).to include("production.key", "--production")
    end

    it "copies it when asked" do
      run("--production", tree)
      expect(File.read(File.join(tree, "config/credentials/production.key"))).to eq("prodkey\n")
    end
  end

  describe "refusing to destroy work" do
    before { write(".env", "SECRET=edited-in-worktree\n", in_dir: tree) }

    it "leaves an existing file alone" do
      run(tree)
      expect(File.read(File.join(tree, ".env"))).to eq("SECRET=edited-in-worktree\n")
    end

    it "reports it as already there rather than as copied" do
      out, = run(tree)
      expect(out).to include("already there")
    end

    it "overwrites only when forced" do
      run("--force", tree)
      expect(File.read(File.join(tree, ".env"))).to eq("SECRET=from-main\n")
    end
  end

  describe "--dry-run" do
    it "writes nothing" do
      run("--dry-run", tree)
      expect(File).not_to exist(File.join(tree, ".env"))
    end

    it "still reports what it would have copied" do
      out, = run("--dry-run", tree)
      expect(out).to include(".env")
    end
  end

  describe "arguments it rejects" do
    # Without a path from inside the main checkout, source and destination are
    # the same tree and every copy is a file onto itself. Reporting success for
    # that is worse than failing.
    it "refuses when source and destination are one checkout" do
      _out, status = run(main)
      expect(status).not_to be_success
    end

    it "fails on a directory that is not a git checkout" do
      plain = File.join(root, "plain")
      FileUtils.mkdir_p(plain)
      _out, status = run(plain)
      expect(status).not_to be_success
    end

    it "fails on a directory that does not exist" do
      _out, status = run(File.join(root, "absent"))
      expect(status).not_to be_success
    end

    it "fails when given two paths" do
      _out, status = run(tree, main)
      expect(status).not_to be_success
    end
  end

  describe "finding the source on its own" do
    # capture3 returns THREE values. Destructuring two here binds `status` to
    # stderr, and a String answers `be_success` with NoMethodError rather than
    # with a verdict, so the expectation fails for a reason unrelated to the
    # script. That cost a debugging round the first time.
    it "needs no path when run from inside the worktree" do
      out, err, status = Open3.capture3({"NO_COLOR" => "1"}, script, chdir: tree)
      expect(status).to be_success, out + err
    end

    it "copies the same files that way" do
      Open3.capture3({"NO_COLOR" => "1"}, script, chdir: tree)
      expect(File.read(File.join(tree, ".env"))).to eq("SECRET=from-main\n")
    end
  end

  describe "a checkout with nothing to copy" do
    let(:bare) { File.join(root, "bare") }
    let(:bare_tree) { File.join(root, "bare-tree") }

    before do
      FileUtils.mkdir_p(bare)
      git(bare, "init", "-q", "-b", "main")
      File.write(File.join(bare, "only.txt"), "x\n")
      git(bare, "add", "-A")
      git(bare, "-c", "user.email=alan.turing@manchester.edu", "-c", "user.name=Alan Turing", "-c", "commit.gpgsign=false",
        "commit", "-qm", "seed")
      git(bare, "worktree", "add", "-q", bare_tree, "-b", "side")
    end

    it "succeeds rather than treating an empty result as a failure" do
      _out, status = run(bare_tree)
      expect(status).to be_success
    end

    it "says so" do
      out, = run(bare_tree)
      expect(out).to include("nothing to copy")
    end
  end
end
