# frozen_string_literal: true

require "open3"
require "pty"
require "tmpdir"
require "yaml"

# `bin/config` is tested the way it is used: as a process, with HOME and
# INSTALL_SOURCES_ROOT pointed at a throwaway tree. `open` and `xdg-open` are
# stubbed on PATH, so no run here ever shows a Finder window.
RSpec.describe "bin/config" do
  let(:script) { File.expand_path("../bin/config", __dir__) }
  let(:target) { File.join(home, ".local", "config", "agentilda-configuration.yml") }
  let(:valid) { YAML.dump("sources" => []) }

  around do |example|
    Dir.mktmpdir("bin-config") do |tmp|
      @tmp = tmp
      @root = File.join(tmp, "repo")
      @home = File.join(tmp, "home")
      @bin = File.join(tmp, "bin")
      [@root, @home, @bin].each { |d| FileUtils.mkdir_p(d) }
      %w[open xdg-open].each { |cmd| stub(cmd, %(echo "$0 $*" >> #{File.join(tmp, "opened").shellescape})) }
      example.run
    end
  end

  attr_reader :tmp, :root, :home, :bin

  # @param name [String] the executable to put first on PATH
  # @param body [String] its shell body
  # @return [String] its path
  def stub(name, body)
    File.join(bin, name).tap do |path|
      File.write(path, "#!/bin/sh\n#{body}\n")
      File.chmod(0o755, path)
    end
  end

  def env(extra = {}) = {"INSTALL_SOURCES_ROOT" => root, "HOME" => home, "NO_COLOR" => "1",
                         "RUBYOPT" => "-W0", "PATH" => "#{bin}:#{ENV["PATH"]}", "EDITOR" => nil}.merge(extra)

  # @return [Array(String, Process::Status)] everything printed, and the exit status
  def run_config(*args, **extra)
    out, err, status = Open3.capture3(env(extra), script, *args)
    [out + err, status]
  end

  # Drives a run through a pseudo-terminal, pressing a key at every prompt.
  #
  # @return [Array(String, Integer)] everything printed, and the exit status
  def interactive(**extra)
    output = +""
    status = nil
    PTY.spawn(env(extra), script) do |reader, writer, pid|
      loop do
        chunk = reader.readpartial(4096)
        output << chunk
        writer.write("x") if chunk.include?("Press any key")
      rescue EOFError, Errno::EIO
        break
      end
      status = Process.wait2(pid).last.exitstatus
    end
    [output, status]
  end

  def write(path, text)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  it "does nothing when ~/.local/config/agentilda-configuration.yml exists" do
    write(target, valid)
    output, status = run_config
    aggregate_failures do
      expect(status).to be_success
      expect(output).to include("already in place")
    end
  end

  it "does nothing when ~/.agentilda-configuration.yml exists" do
    write(File.join(home, ".agentilda-configuration.yml"), valid)
    _output, status = run_config
    aggregate_failures do
      expect(status).to be_success
      expect(File.exist?(target)).to be(false)
    end
  end

  it "seeds from the example and announces the move, without a terminal to edit in" do
    write(File.join(root, "configuration.example.yml"), "# example\n")
    output, status = run_config
    aggregate_failures do
      expect(status).to be_success
      expect(File.read(target)).to eq("# example\n")
      expect(output).to include("has moved to ~/.local/config/agentilda-configuration.yml")
      expect(output).to include("Please edit the file")
      expect(output).to include("no terminal, so no editor")
    end
  end

  it "seeds from the checkout's configuration.yml when there is one" do
    write(File.join(root, "configuration.example.yml"), "# example\n")
    write(File.join(root, "configuration.yml"), "# mine\n")
    output, _status = run_config
    aggregate_failures do
      expect(File.read(target)).to eq("# mine\n")
      expect(output).to include("is no longer read")
    end
  end

  it "backs up the current file before --overwrite replaces it" do
    write(File.join(root, "configuration.example.yml"), "# example\n")
    write(target, "# old\n")
    output, status = run_config("--overwrite")
    backup = output[/backed up \S+ to (\S+)/, 1]
    aggregate_failures do
      expect(status).to be_success
      expect(File.read(backup)).to eq("# old\n")
      expect(File.read(target)).to eq("# example\n")
    end
  end

  it "refuses when there is nothing to seed from" do
    output, status = run_config
    aggregate_failures do
      expect(status.exitstatus).to eq(78)
      expect(output).to include("to seed from")
    end
  end

  it "refuses an argument it does not know" do
    _output, status = run_config("--force")
    expect(status.exitstatus).to eq(64)
  end

  it "prints its usage" do
    output, status = run_config("--help")
    aggregate_failures do
      expect(status).to be_success
      expect(output).to include("--overwrite")
    end
  end

  describe "editing, in a terminal" do
    before { write(File.join(root, "configuration.example.yml"), "bogus: 1\n") }

    # An editor that leaves the file invalid the first time and fixes it the
    # second, which is the loop worth proving.
    let(:editor) do
      count = File.join(tmp, "edits")
      stub("fake-editor", <<~SH)
        n=$(cat #{count.shellescape} 2>/dev/null || echo 0); n=$((n + 1)); echo $n > #{count.shellescape}
        [ $n -ge 2 ] && printf 'sources: []\\n' > "$1"
        exit 0
      SH
    end

    it "reopens the editor until install-sources accepts the file" do
      output, status = interactive("EDITOR" => editor)
      aggregate_failures do
        expect(status).to eq(0)
        expect(output).to include("is not valid yet")
        expect(output).to include("is valid")
        expect(File.read(File.join(tmp, "edits")).strip).to eq("2")
      end
    end

    it "stops on Ctrl-C at the first prompt, keeping the seeded file" do
      output = +""
      status = nil
      PTY.spawn(env, script) do |reader, writer, pid|
        loop do
          chunk = reader.readpartial(4096)
          output << chunk
          writer.write("\u0003") if chunk.include?("Press any key")
        rescue EOFError, Errno::EIO
          break
        end
        status = Process.wait2(pid).last.exitstatus
      end
      aggregate_failures do
        expect(status).to eq(130)
        expect(output).to include("aborted")
        expect(File.read(target)).to eq("bogus: 1\n")
      end
    end
  end
end
