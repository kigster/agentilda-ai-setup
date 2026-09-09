# frozen_string_literal: true

require "json"
require "json_schemer"
require "open3"
require "tmpdir"
require "yaml"

# `configuration.schema.json` and the checks inside `scripts/install-sources`
# say the same thing twice, in two dialects, because neither can do the other's
# job. The schema is what an editor and this suite can read; it cannot run
# inside the installer, which has to work on a machine that has never had a
# bundle. The installer's checks are what actually protect a run; they cannot
# tell an editor anything.
#
# Two statements of one rule drift. So the same bad configurations are fed to
# both here, and both have to refuse them.
RSpec.describe "configuration.schema.json" do
  let(:root) { File.expand_path("..", __dir__) }
  let(:schema) { JSONSchemer.schema(JSON.parse(File.read(File.join(root, "configuration.schema.json")))) }
  let(:script) { File.join(root, "scripts", "install-sources") }

  # @param doc [Hash] a whole configuration
  # @return [Boolean] whether the schema accepts it
  def schema_accepts?(doc) = schema.validate(doc).to_a.empty?

  # Runs the real installer against the document, in a throwaway tree, and
  # reports only whether it refused the configuration. Exit 78 is the
  # ConfigError path; anything else means it got as far as trying to install.
  #
  # @param doc [Hash]
  # @return [Boolean] whether install-sources accepts it
  def installer_accepts?(doc)
    Dir.mktmpdir("schema-agreement") do |dir|
      File.write(File.join(dir, "configuration.yml"), YAML.dump(doc))
      env = {"INSTALL_SOURCES_ROOT" => dir, "NO_COLOR" => "1", "RUBYOPT" => "-W0"}
      _out, _err, status = Open3.capture3(env, script, "list")
      status.exitstatus != 78
    end
  end

  def source(**over)
    {"name" => "up", "type" => "skills", "repo" => "git@example.com:x.git"}.merge(over.transform_keys(&:to_s))
  end

  it "accepts the committed example, which is the file everyone starts from" do
    doc = YAML.safe_load_file(File.join(root, "configuration.example.yml"))
    errors = schema.validate(doc).to_a.map { |e| "#{e["data_pointer"]} #{e["type"]}" }

    expect(errors).to be_empty
  end

  it "declares the 2020-12 dialect, whose unevaluatedProperties this leans on" do
    declared = JSON.parse(File.read(File.join(root, "configuration.schema.json")))["$schema"]

    expect(declared).to eq("https://json-schema.org/draft/2020-12/schema")
  end

  describe "the two agree" do
    # `additionalProperties: false` could not express this one: `repo` is
    # evaluated inside a `oneOf` branch, so it would be rejected along with the
    # typo. Catching the typo while admitting the branch's own keys is what
    # `unevaluatedProperties` is for, and it is why the schema is 2020-12.
    {
      "a plain skills source" => [{}, true],
      "a misspelled include_skills" => [{include_skils: "/x/"}, false],
      "both include_skills and exclude_skills, which apply in order" => [{include_skills: "/a/", exclude_skills: "/b/"}, true],
      "a filter key with nothing under it" => [{include_skills: nil}, false],
      "both agents and exclude_agents" => [{agents: ["claude"], exclude_agents: ["codex"]}, false],
      "install: on a source that clones" => [{install: "true"}, false],
      "a plugin filter on a skills source" => [{include_plugins: "/x/"}, false],
      "adopt: on a skills source" => [{adopt: ["plugins"]}, false],
      "a type nothing implements" => [{type: "wat"}, false]
    }.each do |label, (over, acceptable)|
      it label do
        doc = {"sources" => [source(**over)]}

        aggregate_failures do
          expect(schema_accepts?(doc)).to be(acceptable), "schema disagreed"
          expect(installer_accepts?(doc)).to be(acceptable), "install-sources disagreed"
        end
      end
    end

    {
      "a command source" => [{"name" => "c", "type" => "command", "install" => "true"}, true],
      "a command with nothing to run" => [{"name" => "c", "type" => "command"}, false],
      "repo: on a command source" => [{"name" => "c", "type" => "command", "install" => "t", "repo" => "x"}, false],
      "an adopt: nothing recognises" => [{"name" => "c", "type" => "command", "install" => "t", "adopt" => ["commands"]}, false]
    }.each do |label, (entry, acceptable)|
      it label do
        doc = {"sources" => [entry]}

        aggregate_failures do
          expect(schema_accepts?(doc)).to be(acceptable), "schema disagreed"
          expect(installer_accepts?(doc)).to be(acceptable), "install-sources disagreed"
        end
      end
    end
  end

  describe "keys nothing reads" do
    it "refuses a misspelled top-level key rather than reading past it" do
      doc = {"sorces" => []}

      aggregate_failures do
        expect(schema_accepts?(doc)).to be(false)
        expect(installer_accepts?(doc)).to be(false)
      end
    end

    it "refuses a misspelled key on an agent" do
      doc = {"agents" => [{"name" => "claude", "instaler" => "curl x | sh"}]}

      aggregate_failures do
        expect(schema_accepts?(doc)).to be(false)
        expect(installer_accepts?(doc)).to be(false)
      end
    end
  end
end
