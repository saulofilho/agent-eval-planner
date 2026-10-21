# frozen_string_literal: true

require "set"
require_relative "agent_eval_planner/version"
require_relative "agent_eval_planner/errors"
require_relative "agent_eval_planner/contract_analyzer"
require_relative "agent_eval_planner/vector_catalog"
require_relative "agent_eval_planner/plan_renderer"
require_relative "agent_eval_planner/suite_renderer"
require_relative "agent_eval_planner/remediation_renderer"
require_relative "agent_eval_planner/suite_validator"
require_relative "agent_eval_planner/planner"
require_relative "agent_eval_planner/cli"

module AgentEvalPlanner
  class << self
    def generate(input_path: nil, raw: nil, **options)
      Planner.new(input_path: input_path, raw: raw, **options).call
    end

    def validate_suite(path, known_tools: [], bound_tools: nil, agent_has_no_tools: false,
                       target_components: nil, suites: nil, schema: "auto")
      SuiteValidator.new(
        path: path,
        known_tools: known_tools,
        bound_tools: bound_tools,
        agent_has_no_tools: agent_has_no_tools,
        target_components: target_components,
        suites: suites,
        schema: schema
      ).validate
    end
  end
end
