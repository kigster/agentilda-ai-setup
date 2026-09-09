# frozen_string_literal: true

require "open3"
require "tmpdir"

# The identity half of `bin/agent-lock`, which is the half that has to hold
# still. An agent harness runs every command in a shell of its own, so a
# holder derived from `$$` changed between the call that acquired a lock and
# the call that released it, and the release was refused as somebody else's.
RSpec.describe "bin/agent-lock" do
  let(:script) { File.expand_path("../bin/agent-lock", __dir__) }

  # Each call is its own process, which is the point: the suite may not reuse
  # one shell for acquire and release, or it would not be testing anything.
  #
  # @param args [Array<String>]
  # @param dir [String] the working directory to run in
  # @param env [Hash] anything to add to the environment
  # @return [Array(String, Process::Status)]
  def lock(*args, dir: work, env: {})
    out, err, status = Open3.capture3({"AGENT_LOCK_DIR" => locks}.merge(env), script, *args, chdir: dir)
    [out + err, status]
  end

  # @param output [String] what `acquire` printed
  # @return [String] the holder it named
  def holder_in(output) = output[/holder: (\S+?)\)/, 1]

  around do |example|
    Dir.mktmpdir("agent-lock") do |tmp|
      @tmp = tmp
      @locks = File.join(tmp, "locks")
      @work = File.join(tmp, "work")
      FileUtils.mkdir_p(@work)
      example.run
    end
  end

  attr_reader :tmp, :locks, :work

  describe "identity across processes" do
    it "releases a lock that another process of the same session took" do
      _output, status = lock("acquire", File.join(work, "thing.rb"), "editing")
      expect(status).to be_success

      output, status = lock("release", File.join(work, "thing.rb"))
      aggregate_failures do
        expect(status).to be_success
        expect(output).to include("RELEASED")
      end
    end

    it "lists it as its own between the two" do
      lock("acquire", File.join(work, "thing.rb"), "editing")

      output, _status = lock("mine")
      expect(output).to include("thing.rb")
    end

    it "names a holder anyone can recognise rather than a bare pid" do
      output, _status = lock("acquire", File.join(work, "thing.rb"), "editing")

      expect(holder_in(output)).to match(/\A[a-z][a-zA-Z0-9_.-]*-[0-9a-f]{8}\z/)
    end

    it "re-acquiring says it is already yours rather than refusing" do
      lock("acquire", File.join(work, "thing.rb"), "editing")

      output, status = lock("acquire", File.join(work, "thing.rb"), "editing")
      aggregate_failures do
        expect(status).to be_success
        expect(output).to include("ALREADY YOURS")
      end
    end
  end

  describe "one session, two working trees" do
    it "holds a separate identity in each, so two worktrees do not share locks" do
      other = File.join(tmp, "other-worktree")
      FileUtils.mkdir_p(other)

      here, _status = lock("acquire", File.join(work, "a.rb"), "one")
      there, _status = lock("acquire", File.join(other, "a.rb"), "two", dir: other)

      expect(holder_in(here)).not_to eq(holder_in(there))
    end
  end

  describe "AGENT_ID" do
    it "wins over the fingerprint, so a human can name a session" do
      output, _status = lock("acquire", File.join(work, "thing.rb"), "editing",
        env: {"AGENT_ID" => "leah-researcher"})

      expect(holder_in(output)).to eq("leah-researcher")
    end

    it "refuses to release a lock another identity holds" do
      lock("acquire", File.join(work, "thing.rb"), "editing", env: {"AGENT_ID" => "leah-researcher"})

      output, status = lock("release", File.join(work, "thing.rb"), env: {"AGENT_ID" => "yoda-writer"})
      aggregate_failures do
        expect(status).not_to be_success
        expect(output).to include("REFUSED")
      end
    end
  end
end
