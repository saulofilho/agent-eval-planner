# frozen_string_literal: true

require "json"
require "digest"

module AgentEvalPlanner
  class SuiteRenderer
    def initialize(analyzer:, vectors:)
      @analyzer = analyzer
      @vectors = vectors
    end

    def render
      vectors.map { |vector| JSON.generate(row_for(vector)) }.join("\n") + "\n"
    end

    private

    attr_reader :analyzer, :vectors

    def row_for(vector)
      return native_row(vector) if analyzer.harness == "native"

      legacy_row(vector)
    end

    def legacy_row(vector)
      {
        "id" => stable_id(vector),
        "input" => {
          "target_agent" => analyzer.agent_name,
          "messages" => [{ "role" => "user", "content" => vector.attack_prompt }]
        },
        "expected" => expectations(vector),
        "metadata" => metadata(vector, "plan_id")
      }
    end

    def native_row(vector)
      {
        "id" => stable_id(vector),
        "target_component" => analyzer.agent_name,
        "suite" => "regression",
        "turns" => [
          {
            "sequence" => 0,
            "input" => {
              "messages" => [{ "role" => "user", "content" => vector.attack_prompt }]
            },
            "expectations" => expectations(vector).merge(
              "source_link" => nil,
              "ticket_handoff" => false
            )
          }
        ],
        "metadata" => metadata(vector, "vector_id")
      }
    end

    def expectations(vector)
      {
        "reference_answer" => vector.expected_validation,
        "expected_tools" => [],
        "forbidden_tools" => forbidden_tools_for(vector),
        "refusal" => vector.refusal
      }
    end

    def metadata(vector, link_field)
      {
        "intent" => vector.intent,
        "split" => vector.split,
        "priority" => vector.severity == "P0" ? "high" : "medium",
        "tags" => vector.tags,
        "requires_live_data" => false,
        link_field => vector.id
      }
    end

    def forbidden_tools_for(vector)
      return [] unless analyzer.has_tools?
      return analyzer.tools if vector.refusal || vector.tags.include?("guardrail")

      analyzer.tools
    end

    def stable_id(vector)
      digest = Digest::SHA256.hexdigest("#{vector.id}:#{vector.attack_prompt}")[0, 8]
      slug = vector.id.downcase.gsub(/[^a-z0-9]+/, "-")
      "guardrail-#{slug}-#{digest}"
    end
  end
end
