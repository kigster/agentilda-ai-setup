# frozen_string_literal: true

require "spec_helper"

# A fifteen-minute agent used to sit behind a spinner showing only its name.
# This is what turns `claude --output-format stream-json` into the phrase that
# line has room for.
RSpec.describe SpecPlanBuild::Transcript do
  subject(:transcript) { described_class.new { |phrase| seen << phrase } }

  let(:seen) { [] }

  def assistant(*blocks) = {type: "assistant", message: {content: blocks}}.to_json + "\n"
  def tool(name, input) = {type: "tool_use", name: name, input: input}
  def text(body) = {type: "text", text: body}

  describe "#push" do
    it "reports a tool call as something being done, not as a tool name" do
      transcript.push(assistant(tool("Edit", {"file_path" => "/a/b/spec.md"})))

      expect(seen).to eq(["editing spec.md"])
    end

    it "narrates from what the agent says when it is not calling a tool" do
      transcript.push(assistant(text("Writing the Goals section now. Then the rest.")))

      expect(seen).to eq(["Writing the Goals section now."])
    end

    # An agent that says "now I'll edit the spec" and then edits it is more
    # usefully reported as editing it.
    it "prefers the most recent block in a message" do
      transcript.push(assistant(text("Next I will read the plan."), tool("Read", {"file_path" => "plan.md"})))

      expect(seen).to eq(["reading plan.md"])
    end

    # readpartial splits wherever it likes, so a line arriving in two chunks is
    # the normal case rather than the edge one.
    it "reassembles a line split across chunks" do
      whole = assistant(tool("Write", {"file_path" => "blocked.md"}))
      transcript.push(whole[0, 30])
      transcript.push(whole[30..])

      expect(seen).to eq(["writing blocked.md"])
    end

    it "says nothing twice in a row about the same thing" do
      2.times { transcript.push(assistant(tool("Read", {"file_path" => "spec.md"}))) }

      expect(seen).to eq(["reading spec.md"])
    end

    it "keeps a phrase short enough for one spinner line" do
      transcript.push(assistant(text("x" * 200)))

      expect(seen.first.length).to be <= described_class::LIMIT
    end
  end

  # `claude` reports the failures that matter most as prose, never as an event:
  # the 401 that cost a whole round three minutes an agent printed on stdout
  # and emitted nothing at all.
  describe "output that is not JSON" do
    it "keeps it rather than discarding it" do
      transcript.push("Failed to authenticate. API Error: 401 API key is invalid.\n")

      aggregate_failures do
        expect(transcript.plain).to include("Failed to authenticate. API Error: 401 API key is invalid.")
        expect(seen).to be_empty
      end
    end

    it "survives a line that starts like JSON and is not" do
      expect { transcript.push("{not json at all\n") }.not_to raise_error
    end
  end

  describe "the result event" do
    it "records what the agent finally said" do
      transcript.push({type: "result", subtype: "success", result: "done", is_error: false}.to_json + "\n")

      aggregate_failures do
        expect(transcript.result).to eq("done")
        expect(transcript).not_to be_failed
      end
    end

    it "treats an error result as a failure with the agent's own words" do
      transcript.push({type: "result", result: "hit the turn limit", is_error: true}.to_json + "\n")

      aggregate_failures do
        expect(transcript).to be_failed
        expect(transcript.error).to eq("hit the turn limit")
      end
    end
  end

  describe "#finish" do
    it "consumes a last line that never got its newline" do
      transcript.push(assistant(tool("Bash", {"command" => "bundle exec rspec"})).chomp)
      transcript.finish

      expect(seen).to eq(["running bundle exec rspec"])
    end
  end
end
