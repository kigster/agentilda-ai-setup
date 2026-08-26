# frozen_string_literal: true

require "open3"
require "tmpdir"

# `scripts/install-sources` is a standalone executable rather than a library:
# it belongs to the installer at the root of this repo, not to the gem whose
# suite it rides along in, which is why it reaches two directories up.
# it has to run on a machine that has not seen `bundle install` yet. So it is
# tested the way it is used, by running it, against throwaway git repositories
# on disk and `INSTALL_SOURCES_ROOT` pointed at a throwaway tree. Nothing here
# reaches the network.
RSpec.describe "scripts/install-sources" do
  let(:script) { File.expand_path("../../scripts/install-sources", __dir__) }

  # @param dir [String] where the repository goes
  # @param skills [Array<String>] one SKILL.md-rooted directory per name
  # @param under [String] the subdirectory inside the repo holding them
  # @return [String] dir
  def upstream(dir, skills, under: "skills")
    skills.each do |name|
      FileUtils.mkdir_p(File.join(dir, under, name))
      File.write(File.join(dir, under, name, "SKILL.md"), "---\nname: #{name}\n---\n")
    end
    git(dir, "init", "-q", "-b", "main")
    git(dir, "add", "-A")
    git(dir, "-c", "user.email=alan.turing@manchester.edu", "-c", "user.name=Alan Turing",
      "commit", "-qm", "seed")
    dir
  end

  def git(dir, *args)
    _out, err, status = Open3.capture3("git", "-C", dir, *args)
    raise "git #{args.first} failed: #{err}" unless status.success?
  end

  # @param sources [Array<Hash>] the `sources:` list, written as YAML
  # @return [void]
  def write_config(sources)
    File.write(File.join(root, "configuration.yml"), YAML.dump("sources" => sources))
  end

  # @return [String] the path it wrote
  def write_example(sources)
    File.join(root, "configuration.example.yml").tap do |path|
      File.write(path, YAML.dump("sources" => sources))
    end
  end

  # Runs under RUBYOPT=-W0 deliberately. That silences Kernel#warn, so a script
  # reporting through it says nothing at all, and every expectation on what a
  # run printed then passes or fails on whatever the ambient RUBYOPT happened
  # to be. Pinning it here makes the suite assert the reporting survives.
  #
  # @return [Array(String, Process::Status)] stderr and the exit status
  def install(*)
    env = {"INSTALL_SOURCES_ROOT" => root, "NO_COLOR" => "1", "RUBYOPT" => "-W0"}
    out, err, status = Open3.capture3(env, script, *)
    [out + err, status]
  end

  # @return [Array<String>] what ended up linked into skills/
  def installed_skills = Dir.children(File.join(root, "skills")).sort

  # @return [Array<String>] what ended up copied into plugins/
  def installed_plugins
    dir = File.join(root, "plugins")
    File.directory?(dir) ? Dir.children(dir).sort : []
  end

  # A `type: command` source runs a real command, so the suite needs one. This
  # writes what `npx skills add` writes, without npm and without the network:
  # skills under `.claude/skills/<name>` and bundles under
  # `.claude/plugins/<name>`, both relative to whatever directory it runs in.
  #
  # @param name [String] the executable's filename, so two sources can differ
  # @param skills [Array<String>]
  # @param plugins [Array<String>] each bundle gets one skill of its own inside
  # @param tally [String, nil] a file to append a byte to per invocation
  # @param fail_with [Integer, nil] exit non-zero instead of writing anything
  # @return [String] the command line to put in `install:`
  def installer(name: "fake-installer", skills: [], plugins: [], tally: nil, fail_with: nil,
    root: ".claude", at_git_root: false)
    script = File.join(tmp, name)
    File.write(script, <<~SH)
      #!/usr/bin/env ruby
      require "fileutils"
      # Stands in for an installer with a --local flag, which finds "the current
      # repo" by walking up for a .git and writes at whatever it lands on.
      Dir.chdir(`git rev-parse --show-toplevel`.strip) if #{at_git_root.inspect}
      File.write(#{tally.inspect}, "x", mode: "a") if #{tally.inspect}
      if #{fail_with.inspect}
        $stderr.puts "the registry said no"
        exit #{fail_with.inspect}
      end
      #{skills.inspect}.each do |skill|
        FileUtils.mkdir_p(File.join(#{root.inspect}, "skills", skill))
        File.write(File.join(#{root.inspect}, "skills", skill, "SKILL.md"), "---\nname: \#{skill}\n---\n")
      end
      #{plugins.inspect}.each do |plugin|
        inner = File.join(#{root.inspect}, "plugins", plugin, "skills", "\#{plugin}-skill")
        FileUtils.mkdir_p(inner)
        File.write(File.join(inner, "SKILL.md"), "---\nname: \#{plugin}-skill\n---\n")
        File.write(File.join(#{root.inspect}, "plugins", plugin, "plugin.json"), "{}")
      end
    SH
    File.chmod(0o755, script)
    script
  end

  around do |example|
    Dir.mktmpdir("install-sources") do |tmp|
      @tmp = tmp
      @root = File.join(tmp, "repo")
      FileUtils.mkdir_p(@root)
      example.run
    end
  end

  attr_reader :tmp, :root

  describe "with no filter" do
    it "installs every skill the source carries" do
      repo = upstream(File.join(tmp, "up"), %w[alpha beta gamma])
      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills"}])

      _output, status = install
      expect(status).to be_success
      expect(installed_skills).to eq(%w[alpha beta gamma])
    end
  end

  describe "include_skills" do
    it "installs only the skills whose name matches" do
      repo = upstream(File.join(tmp, "up"), %w[alpha beta gamma])
      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills",
                     "include_skills" => "/\\A(alpha|gamma)\\z/"}])

      _output, status = install
      expect(status).to be_success
      expect(installed_skills).to eq(%w[alpha gamma])
    end

    it "accepts a bare pattern and regexp flags" do
      repo = upstream(File.join(tmp, "up"), %w[Alpha beta])
      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills",
                     "include_skills" => "/alpha/i"}])

      expect(install.last).to be_success
      expect(installed_skills).to eq(%w[Alpha])
    end

    it "matches the installed name, not the path inside the source" do
      repo = upstream(File.join(tmp, "up"), %w[engineering/alpha deprecated/beta])
      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills",
                     "include_skills" => "/\\Aalpha\\z/"}])

      expect(install.last).to be_success
      expect(installed_skills).to eq(%w[alpha])
    end
  end

  describe "exclude_skills" do
    it "installs everything except the skills whose name matches" do
      repo = upstream(File.join(tmp, "up"), %w[alpha beta gamma])
      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills",
                     "exclude_skills" => "/\\Abeta\\z/"}])

      _output, status = install
      expect(status).to be_success
      expect(installed_skills).to eq(%w[alpha gamma])
    end

    it "names what it skipped" do
      repo = upstream(File.join(tmp, "up"), %w[alpha beta])
      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills",
                     "exclude_skills" => "/beta/"}])

      output, _status = install
      expect(output).to include("exclude_skills /beta/ skipped 1 of 2: beta")
    end
  end

  describe "a plugin source" do
    it "filters the fan-out into skills/ but keeps the bundle whole" do
      repo = upstream(File.join(tmp, "up"), %w[alpha beta])
      write_config([{"name" => "up", "type" => "plugin", "repo" => repo,
                     "include_skills" => "/\\Aalpha\\z/"}])

      expect(install.last).to be_success
      expect(installed_skills).to eq(%w[alpha])
      expect(Dir.children(File.join(root, "plugins", "up", "skills")).sort).to eq(%w[alpha beta])
    end
  end

  describe "tightening a filter after the fact" do
    it "unlinks the skills it installed last time and no longer installs" do
      repo = upstream(File.join(tmp, "up"), %w[alpha beta gamma])
      source = {"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills"}
      write_config([source])
      expect(install.last).to be_success
      expect(installed_skills).to eq(%w[alpha beta gamma])

      write_config([source.merge("include_skills" => "/\\Abeta\\z/")])
      output, status = install
      expect(status).to be_success
      expect(output).to include("dropped by up")
      expect(installed_skills).to eq(%w[beta])
    end

    it "previews the unlinking under --dry-run without doing it" do
      repo = upstream(File.join(tmp, "up"), %w[alpha beta])
      source = {"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills"}
      write_config([source])
      install

      write_config([source.merge("exclude_skills" => "/alpha/")])
      output, status = install("--dry-run")
      expect(status).to be_success
      expect(output).to include("skills/alpha: dropped by up")
      expect(installed_skills).to eq(%w[alpha beta])
    end

    it "leaves a skill alone when the source it came from could not be enumerated" do
      repo = upstream(File.join(tmp, "up"), %w[alpha beta])
      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills"}])
      install

      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "nowhere"}])
      _output, status = install
      expect(status).to be_success
      expect(installed_skills).to eq(%w[alpha beta])
    end
  end

  describe "a config it will not guess past" do
    it "refuses a source that sets both filters" do
      repo = upstream(File.join(tmp, "up"), %w[alpha])
      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills",
                     "include_skills" => "/alpha/", "exclude_skills" => "/beta/"}])

      output, status = install
      expect(status).not_to be_success
      expect(output).to include("include_skills and exclude_skills are both set")
      expect(File.directory?(File.join(root, "skills"))).to be false
    end

    it "refuses a pattern that does not compile" do
      repo = upstream(File.join(tmp, "up"), %w[alpha])
      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills",
                     "include_skills" => "/alpha(/"}])

      output, status = install
      expect(status).not_to be_success
      expect(output).to include("is not a valid regular expression")
    end
  end

  describe "list" do
    it "reports the filter alongside the source" do
      repo = upstream(File.join(tmp, "up"), %w[alpha])
      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills",
                     "exclude_skills" => "/\\Aalpha\\z/"}])

      output, status = install("list")
      expect(status).to be_success
      expect(output).to include("exclude_skills /\\Aalpha\\z/")
    end
  end
  # `npx skills add …` and friends install a skill without a repository to
  # clone. Running the command inside `.sources/<name>` rather than letting it
  # write to ~/.claude/skills is what keeps its output inside the manifest,
  # the filters and the prune that every other source type relies on.
  describe "a command source" do
    it "installs the skills the command wrote" do
      write_config([{"name" => "cmd", "type" => "command",
                     "install" => installer(skills: %w[alpha beta])}])

      _output, status = install
      expect(status).to be_success
      expect(installed_skills).to eq(%w[alpha beta])
    end

    it "installs the plugin bundles the command wrote, and their skills with them" do
      write_config([{"name" => "cmd", "type" => "command",
                     "install" => installer(plugins: %w[quota])}])

      install
      aggregate_failures do
        expect(installed_plugins).to eq(%w[quota])
        expect(installed_skills).to eq(%w[quota-skill])
        expect(File).to exist(File.join(root, "plugins", "quota", "plugin.json"))
      end
    end

    # npx re-downloads its package every time, and install-sources is run
    # several times a day.
    it "runs the command once and leaves it alone on the next run" do
      tally = File.join(tmp, "runs")
      write_config([{"name" => "cmd", "type" => "command",
                     "install" => installer(skills: %w[alpha], tally: tally)}])

      2.times { install }

      aggregate_failures do
        expect(File.read(tally).size).to eq(1)
        expect(installed_skills).to eq(%w[alpha])
      end
    end

    it "runs it again under --force, which is what wipes .sources" do
      tally = File.join(tmp, "runs")
      write_config([{"name" => "cmd", "type" => "command",
                     "install" => installer(skills: %w[alpha], tally: tally)}])

      install
      install("-f")

      expect(File.read(tally).size).to eq(2)
    end

    it "reports a command that failed, and installs nothing" do
      write_config([{"name" => "cmd", "type" => "command",
                     "install" => installer(fail_with: 3)}])

      output, status = install
      aggregate_failures do
        expect(output).to include("exited 3").and include("the registry said no")
        expect(installed_skills).to be_empty
        expect(status).to be_success
      end
    end

    it "says so when the command is not on PATH rather than dying" do
      write_config([{"name" => "cmd", "type" => "command", "install" => "definitely-not-a-command --yes"}])

      output, status = install
      aggregate_failures do
        expect(output).to include("not on PATH")
        expect(status).to be_success
      end
    end

    it "takes filters like any other source" do
      write_config([{"name" => "cmd", "type" => "command",
                     "install" => installer(skills: %w[alpha beta gamma]),
                     "include_skills" => "/\\A(alpha|gamma)\\z/"}])

      install
      expect(installed_skills).to eq(%w[alpha gamma])
    end

    # The whole reason the command runs inside .sources: what it wrote is an
    # ordinary source tree, so tightening a filter takes a skill back.
    it "unlinks what a tightened filter no longer admits" do
      command = installer(skills: %w[alpha beta])
      write_config([{"name" => "cmd", "type" => "command", "install" => command}])
      install
      expect(installed_skills).to eq(%w[alpha beta])

      write_config([{"name" => "cmd", "type" => "command", "install" => command,
                     "exclude_skills" => "/\\Abeta\\z/"}])
      install

      expect(installed_skills).to eq(%w[alpha])
    end

    it "lists the command it runs, and whether it has run" do
      write_config([{"name" => "cmd", "type" => "command", "install" => installer(skills: %w[alpha])}])

      before, = install("list")
      install
      after, = install("list")

      aggregate_failures do
        expect(before).to include("fake-installer").and include("not run")
        expect(after).to include("installed")
      end
    end
  end

  # One command can write a bundle and some loose skills at once, and wanting
  # only one half of that is a normal thing to want.
  describe "adopt" do
    let(:both) { installer(skills: %w[alpha], plugins: %w[quota]) }

    it "takes both halves by default" do
      write_config([{"name" => "cmd", "type" => "command", "install" => both}])

      install
      aggregate_failures do
        expect(installed_plugins).to eq(%w[quota])
        expect(installed_skills).to eq(%w[alpha quota-skill])
      end
    end

    it "takes the skills and leaves the bundle" do
      write_config([{"name" => "cmd", "type" => "command", "install" => both, "adopt" => ["skills"]}])

      install
      aggregate_failures do
        expect(installed_plugins).to be_empty
        expect(installed_skills).to eq(%w[alpha])
      end
    end

    it "takes the bundle and leaves the skills, its own included" do
      write_config([{"name" => "cmd", "type" => "command", "install" => both, "adopt" => ["plugins"]}])

      install
      aggregate_failures do
        expect(installed_plugins).to eq(%w[quota])
        expect(installed_skills).to be_empty
      end
    end
  end

  describe "include_plugins and exclude_plugins" do
    it "installs only the bundles whose name matches" do
      write_config([{"name" => "cmd", "type" => "command",
                     "install" => installer(plugins: %w[quota ledger]),
                     "include_plugins" => "/\\Aquota\\z/"}])

      install
      expect(installed_plugins).to eq(%w[quota])
    end

    it "installs every bundle except those whose name matches" do
      write_config([{"name" => "cmd", "type" => "command",
                     "install" => installer(plugins: %w[quota ledger]),
                     "exclude_plugins" => "/\\Aquota\\z/"}])

      install
      expect(installed_plugins).to eq(%w[ledger])
    end

    it "skips the skills of a bundle it did not install" do
      write_config([{"name" => "cmd", "type" => "command",
                     "install" => installer(plugins: %w[quota ledger]),
                     "exclude_plugins" => "/\\Aquota\\z/"}])

      install
      expect(installed_skills).to eq(%w[ledger-skill])
    end

    it "applies to a plain plugin source too" do
      repo = upstream(File.join(tmp, "up"), %w[alpha], under: "pstack/skills")
      write_config([{"name" => "pstack", "type" => "plugin", "repo" => repo, "path" => "pstack",
                     "exclude_plugins" => "/\\Apstack\\z/"}])

      install
      aggregate_failures do
        expect(installed_plugins).to be_empty
        expect(installed_skills).to be_empty
      end
    end
  end

  # Every one of these is a typo whose quiet outcome looks enough like success
  # to go unnoticed, so the run stops instead of degrading.
  describe "a command source it will not guess past" do
    def refuses(source, saying)
      write_config([source])
      output, status = install

      aggregate_failures do
        expect(status.exitstatus).to eq(78)
        expect(output).to include(saying)
      end
    end

    it "refuses a command source with nothing to run" do
      refuses({"name" => "cmd", "type" => "command"}, "needs an `install:`")
    end

    it "refuses a command source that also names a repo" do
      refuses({"name" => "cmd", "type" => "command", "install" => "true", "repo" => "git@example.com:x.git"},
        "would be ignored")
    end

    it "refuses an install: on a source that clones" do
      refuses({"name" => "up", "type" => "skills", "repo" => "git@example.com:x.git", "install" => "true"},
        "only runs on a type: command source")
    end

    it "refuses adopt: on a source that has only skills to give" do
      refuses({"name" => "up", "type" => "skills", "repo" => "git@example.com:x.git", "adopt" => ["plugins"]},
        "means nothing on a type: skills source")
    end

    it "refuses an adopt: it does not recognise" do
      refuses({"name" => "cmd", "type" => "command", "install" => "true", "adopt" => ["commands"]},
        "expected skills or plugins")
    end

    it "refuses a plugin filter on a source that installs no bundles" do
      refuses({"name" => "up", "type" => "skills", "repo" => "git@example.com:x.git",
               "include_plugins" => "/x/"}, "installs no plugin bundles")
    end

    it "refuses a source that both allows and denies the same kind" do
      refuses({"name" => "cmd", "type" => "command", "install" => "true",
               "include_plugins" => "/x/", "exclude_plugins" => "/y/"},
        "include_plugins and exclude_plugins are both set")
    end
  end
  # `install` here never has a terminal: Open3 gives the child a pipe. That is
  # the same shape as cron, CI or an agent harness, and the branch that matters
  # most, because it is the one where nobody is watching.
  describe "a first run with no configuration.yml" do
    it "seeds one from the example, and installs nothing until it has been read" do
      write_example([{"name" => "up", "type" => "skills", "repo" => "/nowhere", "path" => "skills"}])

      output, status = install
      aggregate_failures do
        expect(status).to be_success
        expect(output).to include("seeded configuration.yml")
        expect(File.file?(File.join(root, "configuration.yml"))).to be(true)
        expect(File.exist?(File.join(root, "skills"))).to be(false)
      end
    end

    it "installs on the next run, now that the file is there" do
      repo = upstream(File.join(tmp, "up"), %w[alpha])
      write_example([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills"}])

      install
      _output, status = install

      aggregate_failures do
        expect(status).to be_success
        expect(installed_skills).to eq(%w[alpha])
      end
    end

    it "says so when there is no example to seed from either" do
      output, status = install
      aggregate_failures do
        expect(status.exitstatus).to eq(78)
        expect(output).to include("no configuration.yml")
      end
    end
  end
  # `sh` stands in for an installed agent: every machine that can run this
  # suite has one on PATH, and none has an executable called
  # `definitely-not-an-agent`, so neither case needs PATH rearranged under it.
  describe "agents" do
    def write_agents(agents)
      File.write(File.join(root, "configuration.yml"), YAML.dump("agents" => agents))
    end

    it "says where it found an agent that is already installed" do
      write_agents([{"name" => "sh"}])

      output, status = install("agents")
      aggregate_failures do
        expect(status).to be_success
        expect(output).to match(%r{/sh\b})
      end
    end

    it "shows the command it would run for one that is missing" do
      write_agents([{"name" => "definitely-not-an-agent", "installer" => "curl https://example.com | sh"}])

      output, _status = install("agents")
      expect(output).to include("not installed").and include("curl https://example.com | sh")
    end

    it "says so when a missing agent has no installer to run" do
      write_agents([{"name" => "definitely-not-an-agent"}])

      expect(install("agents").first).to include("no installer:")
    end

    it "names the command rather than running it under --dry-run" do
      write_agents([{"name" => "definitely-not-an-agent", "installer" => "exit 3"}])

      output, status = install("-n", "agents", "install")
      aggregate_failures do
        expect(status).to be_success
        expect(output).to include("would run: exit 3")
      end
    end

    it "reports an installer that failed" do
      write_agents([{"name" => "definitely-not-an-agent", "installer" => "exit 3"}])

      expect(install("agents", "install").first).to include("exited 3")
    end

    it "refuses a name that is not on the list" do
      write_agents([{"name" => "sh"}])

      output, status = install("agents", "install", "nosuch")
      aggregate_failures do
        expect(status.exitstatus).to eq(78)
        expect(output).to include("not listed under agents: nosuch")
      end
    end

    it "refuses an entry with no name" do
      write_agents([{"installer" => "true"}])

      output, status = install("agents")
      aggregate_failures do
        expect(status.exitstatus).to eq(78)
        expect(output).to include("has no name")
      end
    end
  end
  describe "agent targeting" do
    def write_config_with_agents(agents, sources)
      File.write(File.join(root, "configuration.yml"),
        YAML.dump("agents" => agents, "sources" => sources))
    end

    let(:agents) { [{"name" => "claude"}, {"name" => "codex"}] }

    it "installs a source aimed at an agent this machine is configured for" do
      repo = upstream(File.join(tmp, "up"), %w[alpha])
      write_config_with_agents(agents,
        [{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills", "agents" => ["claude"]}])

      install
      expect(installed_skills).to eq(%w[alpha])
    end

    it "skips one aimed at an agent that is neither installed nor listed, and says which" do
      repo = upstream(File.join(tmp, "up"), %w[alpha])
      write_config_with_agents(agents,
        [{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills", "agents" => ["kiro"]}])

      output, status = install
      aggregate_failures do
        expect(status).to be_success
        expect(output).to include("for kiro")
        expect(installed_skills).to be_empty
      end
    end

    it "takes back what it installed when the targeting later excludes it" do
      repo = upstream(File.join(tmp, "up"), %w[alpha])
      source = {"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills"}

      write_config_with_agents(agents, [source])
      install
      expect(installed_skills).to eq(%w[alpha])

      write_config_with_agents(agents, [source.merge("agents" => ["kiro"])])
      install
      expect(installed_skills).to be_empty
    end

    it "installs when exclude_agents leaves somebody who would read it" do
      repo = upstream(File.join(tmp, "up"), %w[alpha])
      write_config_with_agents(agents,
        [{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills",
          "exclude_agents" => ["codex"]}])

      install
      expect(installed_skills).to eq(%w[alpha])
    end

    it "skips when exclude_agents names every agent there is" do
      repo = upstream(File.join(tmp, "up"), %w[alpha])
      write_config_with_agents(agents,
        [{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills",
          "exclude_agents" => %w[claude codex]}])

      expect(install.first).to include("excluded from claude, codex")
    end

    it "ignores targeting entirely when nothing declares any agents" do
      repo = upstream(File.join(tmp, "up"), %w[alpha])
      write_config([{"name" => "up", "type" => "skills", "repo" => repo, "path" => "skills",
                     "agents" => ["kiro"]}])

      install
      expect(installed_skills).to eq(%w[alpha])
    end

    it "refuses a source that both names and excludes agents" do
      write_config_with_agents(agents,
        [{"name" => "up", "type" => "skills", "repo" => "git@example.com:x.git",
          "agents" => ["claude"], "exclude_agents" => ["codex"]}])

      output, status = install
      aggregate_failures do
        expect(status.exitstatus).to eq(78)
        expect(output).to include("agents and exclude_agents are both set")
      end
    end

    it "refuses agents written as anything but a list of names" do
      write_config_with_agents(agents,
        [{"name" => "up", "type" => "skills", "repo" => "git@example.com:x.git", "agents" => "claude"}])

      output, status = install
      aggregate_failures do
        expect(status.exitstatus).to eq(78)
        expect(output).to include("must be a list of names")
      end
    end

    it "refuses an empty agents list rather than reading it as none" do
      write_config_with_agents(agents,
        [{"name" => "up", "type" => "skills", "repo" => "git@example.com:x.git", "agents" => []}])

      output, status = install
      aggregate_failures do
        expect(status.exitstatus).to eq(78)
        expect(output).to include("leave it out to mean every agent")
      end
    end
  end
  # A repository that files its skills as `<thing>/skills/SKILL.md` rather than
  # `<thing>/skills/<name>/SKILL.md` gives every one of them the same basename,
  # and the fan-out names a skill after its directory. Real repositories do
  # this; ahmedasmar/devops-claude-skills has six.
  describe "two skills that would install under one name" do
    it "keeps the first, names both directories, and does not claim it installed both" do
      dir = File.join(tmp, "up")
      %w[alpha beta].each do |group|
        FileUtils.mkdir_p(File.join(dir, group, "skills"))
        File.write(File.join(dir, group, "skills", "SKILL.md"), "---\nname: #{group}\n---\n")
      end
      git(dir, "init", "-q", "-b", "main")
      git(dir, "add", "-A")
      git(dir, "-c", "user.email=alan.turing@manchester.edu", "-c", "user.name=Alan Turing",
        "commit", "-qm", "seed")
      write_config([{"name" => "up", "type" => "skills", "repo" => dir}])

      output, status = install
      aggregate_failures do
        expect(status).to be_success
        expect(installed_skills).to eq(%w[skills])
        expect(output).to include("would install both").and include("alpha/skills").and include("beta/skills")
      end
    end
  end
  # `npx skills add` writes .claude/; Braintrust's `bt setup skills` writes
  # .agents/ even when told --agent claude. Both are real, so both are looked
  # for, and a command source is not required to know which convention its
  # installer follows.
  describe "a command that writes somewhere other than .claude" do
    it "adopts what it left under .agents" do
      write_config([{"name" => "cmd", "type" => "command",
                     "install" => installer(skills: %w[alpha], root: ".agents")}])

      install
      expect(installed_skills).to eq(%w[alpha])
    end
  end

  # An installer told to configure "the current repo" walks up for a .git, and
  # from inside .sources/<name> the first one it meets is the tree this script
  # is installing into. Staging is a repository of its own so the walk stops
  # where the containment does.
  describe "an installer that writes at the git root it finds" do
    it "finds the staging directory rather than the tree above it" do
      # The tree being installed into is itself a repository, which is the
      # normal case: this script lives in one. Without staging being a
      # repository of its own, the installer walks up and lands here.
      git(root, "init", "-q", "-b", "main")

      write_config([{"name" => "cmd", "type" => "command",
                     "install" => installer(skills: %w[alpha], at_git_root: true)}])

      install
      aggregate_failures do
        expect(installed_skills).to eq(%w[alpha])
        expect(File.directory?(File.join(root, ".sources", "cmd", ".claude", "skills", "alpha"))).to be(true)
        expect(File.exist?(File.join(root, ".claude"))).to be(false)
      end
    end
  end
end
