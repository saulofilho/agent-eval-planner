# frozen_string_literal: true

require "tmpdir"

RSpec.describe AgentEvalPlanner do
  describe ".generate" do
    let(:result) do
      described_class.generate(
        input_path: FIXTURE_PATH,
        team: "Platform Team",
        tools: %w[funnel_analytics open_service_center_ticket]
      )
    end

    it "generates a markdown plan with smoke pack" do
      expect(result.plan).to include("# Platform Team — Plano de Ação de Eval de Agente")
      expect(result.plan).to include("SCOPE-01")
      expect(result.plan).to include("INJECT-01")
      expect(result.plan).to include("ROLE-01")
      expect(result.plan).to include("bolo de cenoura")
    end

    it "fills forbidden_tools in the suite" do
      lines = result.suite.lines.map { |l| JSON.parse(l) }
      smoke = lines.find { |row| row.dig("metadata", "plan_id") == "SCOPE-01" }
      expect(smoke["expected"]["forbidden_tools"]).to include("funnel_analytics")
      expect(smoke["expected"]["refusal"]).to eq(true)
    end

    it "generates remediations with quick wins" do
      expect(result.remediations).to include("Quick wins")
      expect(result.remediations).to include("SCOPE-01")
    end
  end

  describe ".validate_suite" do
    it "accepts a valid generated suite" do
      result = described_class.generate(input_path: FIXTURE_PATH, tools: %w[funnel_analytics])

      Dir.mktmpdir do |dir|
        path = File.join(dir, "suite.jsonl")
        File.write(path, result.suite)
        errors = described_class.validate_suite(path, known_tools: %w[funnel_analytics])
        expect(errors).to be_empty
      end
    end

    it "hard-fails empty forbidden_tools on guardrail rows" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "bad.jsonl")
        File.write(
          path,
          JSON.generate(
            "id" => "bad-1",
            "expected" => { "forbidden_tools" => [], "refusal" => true },
            "metadata" => { "intent" => "out_of_scope_refusal", "tags" => ["scope"] }
          )
        )
        errors = described_class.validate_suite(path, known_tools: %w[funnel_analytics])
        expect(errors.join).to match(/HARD FAIL|forbidden_tools/)
      end
    end
  end
end
