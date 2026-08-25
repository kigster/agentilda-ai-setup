# frozen_string_literal: true

require "open3"
require "tmpdir"

# `bin/install` is a standalone shell executable, so it is tested the way it is
# used: by running it against a throwaway checkout, with $HOME pointed at a
# throwaway directory. Every example here asserts on what landed on disk rather
# than on what the run said it did.
RSpec.describe "bin/install" do
  let(:repo_bin) { File.expand_path("../../bin", __dir__) }

  # A checkout with one of everything the copy table names, including a skill
  # that is a symlink into a sibling directory — which is the shape
  # install-sources leaves behind, and the reason the copy resolves links.
  #
  # @return [String] the checkout's path
  def checkout
    root = File.join(tmp, "checkout")
    FileUtils.mkdir_p(File.join(root, "bin"))
    %w[install setup].each do |name|
      FileUtils.cp(File.join(repo_bin, name), File.join(root, "bin", name))
      FileUtils.chmod(0o755, File.join(root, "bin", name))
    end

    write(root, "config/AGENTS.md", "# instructions\n")
    write(root, "src/commands/plan-run.md", "# a command\n")
    write(root, "workflow/agents/yoda-writer.md", "# a specialist\n")
    write(root, "context/postgresql.md", "# reference\n")

    # The real skill lives outside skills/, and skills/ holds a link to it.
    write(root, "src/skills/create-plan/SKILL.md", "---\nname: create-plan\n---\n")
    FileUtils.mkdir_p(File.join(root, "skills"))
    FileUtils.ln_s(File.join(root, "src", "skills", "create-plan"),
      File.join(root, "skills", "create-plan"))
    root
  end

  def write(root, path, body)
    full = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, body)
  end

  # @return [Array(String, Process::Status)] output and status
  def install(*args, root: checkout)
    env = {"HOME" => home, "NO_COLOR" => "1"}
    out, err, status = Open3.capture3(env, File.join(root, "bin", "install"), *args)
    [out + err, status]
  end

  def agents_dir = File.join(home, ".agents")

  def claude_dir = File.join(home, ".claude")

  around do |example|
    Dir.mktmpdir("bin-install") do |dir|
      @tmp = dir
      @home = File.join(dir, "home")
      FileUtils.mkdir_p(@home)
      example.run
    end
  end

  attr_reader :tmp, :home

  describe "the copy" do
    it "flattens the checkout into the layout bin/setup already expects" do
      _output, status = install

      aggregate_failures do
        expect(status).to be_success
        expect(File.file?(File.join(agents_dir, "config", "AGENTS.md"))).to be(true)
        expect(File.file?(File.join(agents_dir, "commands", "plan-run.md"))).to be(true)
        expect(File.file?(File.join(agents_dir, "agents", "yoda-writer.md"))).to be(true)
        expect(File.file?(File.join(agents_dir, "context", "postgresql.md"))).to be(true)
      end
    end

    it "resolves every symlink, so what it leaves behind needs no checkout" do
      install
      copied = File.join(agents_dir, "skills", "create-plan")

      aggregate_failures do
        expect(File.symlink?(copied)).to be(false)
        expect(File.file?(File.join(copied, "SKILL.md"))).to be(true)
        expect(Dir.glob(File.join(agents_dir, "**/*"), File::FNM_DOTMATCH)
                  .select { |f| File.symlink?(f) }).to be_empty
      end
    end

    it "survives the checkout being deleted afterwards" do
      root = checkout
      install(root:)
      FileUtils.rm_rf(root)

      expect(File.read(File.join(agents_dir, "skills", "create-plan", "SKILL.md")))
        .to include("create-plan")
    end

    it "says what is not in this checkout rather than failing on it" do
      output, status = install

      aggregate_failures do
        expect(status).to be_success
        expect(output).to include("plugins").and include("not in this checkout")
      end
    end
  end

  describe "what it will not overwrite" do
    it "leaves an existing tree alone and says which parts it refused" do
      root = checkout
      install(root:)
      File.write(File.join(agents_dir, "context", "postgresql.md"), "edited by hand\n")

      output, _status = install(root:)

      aggregate_failures do
        expect(output).to include("already there").and include("conflicts 5")
        expect(File.read(File.join(agents_dir, "context", "postgresql.md"))).to eq("edited by hand\n")
      end
    end

    it "replaces it under --force" do
      root = checkout
      install(root:)
      File.write(File.join(agents_dir, "context", "postgresql.md"), "edited by hand\n")

      install("--force", root:)

      expect(File.read(File.join(agents_dir, "context", "postgresql.md"))).to eq("# reference\n")
    end

    # ~/.agents being a link to a checkout is the arrangement this replaces, and
    # replacing it is what breaks a machine already set up that way.
    it "refuses to replace a symlinked ~/.agents without being told to" do
      FileUtils.ln_s(tmp, agents_dir)

      output, status = install

      aggregate_failures do
        expect(status.exitstatus).to eq(65)
        expect(output).to include("is a symlink")
        expect(File.symlink?(agents_dir)).to be(true)
      end
    end

    it "replaces the symlink under --force" do
      FileUtils.ln_s(tmp, agents_dir)

      install("--force")

      aggregate_failures do
        expect(File.symlink?(agents_dir)).to be(false)
        expect(File.directory?(agents_dir)).to be(true)
      end
    end

    it "writes nothing at all under --dry-run" do
      output, status = install("--dry-run")

      aggregate_failures do
        expect(status).to be_success
        expect(output).to include("dry run")
        expect(File.exist?(agents_dir)).to be(false)
        expect(File.exist?(claude_dir)).to be(false)
      end
    end
  end

  describe "the linking step it hands off to" do
    it "links ~/.agents into ~/.claude, relative to the home it was given" do
      install

      aggregate_failures do
        expect(File.readlink(File.join(claude_dir, "commands"))).to eq("../.agents/commands")
        expect(File.readlink(File.join(claude_dir, "CLAUDE.md"))).to eq("../.agents/config/AGENTS.md")
        expect(File.readlink(File.join(home, "AGENTS.md"))).to eq(".agents/config/AGENTS.md")
      end
    end

    it "stops before it under --no-setup" do
      install("--no-setup")

      aggregate_failures do
        expect(File.directory?(agents_dir)).to be(true)
        expect(File.exist?(claude_dir)).to be(false)
      end
    end

    it "writes nothing outside the home it was given" do
      install

      # Every link it wrote is relative and stays inside $HOME, so a tree built
      # under one home cannot reach into another — which is what makes running
      # this against a throwaway home a real test rather than a hopeful one.
      written = Dir.glob(File.join(home, "**/*"), File::FNM_DOTMATCH)
        .select { |f| File.symlink?(f) }
        .map { |f| File.readlink(f) }

      aggregate_failures do
        expect(written).not_to be_empty
        expect(written.grep(%r{\A/})).to be_empty
        expect(written.grep(/#{Regexp.escape(Dir.home)}/)).to be_empty
      end
    end
  end
end
