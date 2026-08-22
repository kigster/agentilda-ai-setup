# frozen_string_literal: true

require "open3"
require "tmpdir"

# `scripts/install-sources` is a standalone executable rather than a library:
# it has to run on a machine that has not seen `bundle install` yet. So it is
# tested the way it is used, by running it, against throwaway git repositories
# on disk and `INSTALL_SOURCES_ROOT` pointed at a throwaway tree. Nothing here
# reaches the network.
RSpec.describe "scripts/install-sources" do
  let(:script) { File.expand_path("../scripts/install-sources", __dir__) }

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
    FileUtils.mkdir_p(File.join(root, "config"))
    File.write(File.join(root, "config", "sources.yml"), YAML.dump("sources" => sources))
  end

  # @return [Array(String, Process::Status)] stderr and the exit status
  def install(*args)
    out, err, status = Open3.capture3({"INSTALL_SOURCES_ROOT" => root, "NO_COLOR" => "1"}, script, *args)
    [out + err, status]
  end

  # @return [Array<String>] what ended up linked into skills/
  def installed_skills = Dir.children(File.join(root, "skills")).sort

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
end
