# frozen_string_literal: true

# A seam, not a client library. What is worth testing is the failure
# reporting: Linear declines a mutation in three different ways, and two of
# them are not errors.
RSpec.describe Agentilda::Linear::API do
  subject(:api) { described_class.new(transport:) }

  let(:transport) { ->(_document, _variables) { response } }
  let(:response) { {"data" => {}} }

  describe "authentication" do
    it "refuses to be built with no way to authenticate" do
      allow(ENV).to receive(:[]).with("LINEAR_API_KEY").and_return(nil)

      expect { described_class.new }
        .to raise_error(Agentilda::Error, /Set LINEAR_API_KEY.*--format json/m)
    end

    it "is content with a token" do
      expect { described_class.new(token: "lin_api_x") }.not_to raise_error
    end
  end

  describe "#team" do
    let(:response) do
      {"data" => {"teams" => {"nodes" => [{"id" => "t-1", "name" => "Tax", "key" => "TAX",
                                           "states" => {"nodes" => [{"id" => "s-1"}]},
                                           "labels" => {"nodes" => []}}]}}}
    end

    it "returns the team with its states and labels in one round trip" do
      expect(api.team("tax")).to include(id: "t-1", key: "TAX", states: [{"id" => "s-1"}])
    end

    context "when no team wears that key" do
      let(:response) { {"data" => {"teams" => {"nodes" => []}}} }

      it "says which key it looked for" do
        expect { api.team("nope") }.to raise_error(Agentilda::Error, /no Linear team has the key NOPE/)
      end
    end
  end

  describe "reporting a refusal" do
    context "when Linear returns errors" do
      let(:response) { {"errors" => [{"message" => "Entity not found"}, {"message" => "and again"}]} }

      it "repeats what Linear actually said" do
        expect { api.query("query { x }") }
          .to raise_error(Agentilda::Error, /Entity not found; and again/)
      end
    end

    # A failed mutation comes back as `success: false` with no errors array,
    # which reads as a success to anything only checking for errors.
    context "when a mutation reports itself unsuccessful" do
      let(:response) { {"data" => {"issueCreate" => {"success" => false, "issue" => nil}}} }

      it "does not mistake it for having worked" do
        expect { api.create_issue(title: "x") }
          .to raise_error(Agentilda::Error, /declined the issueCreate/)
      end
    end

    context "when the response has neither data nor errors" do
      let(:response) { {} }

      it "says so rather than returning nil into the caller" do
        expect { api.query("query { x }") }.to raise_error(Agentilda::Error, /returned no data/)
      end
    end
  end
end
