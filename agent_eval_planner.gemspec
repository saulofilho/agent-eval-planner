# frozen_string_literal: true

require_relative "lib/agent_eval_planner/version"

Gem::Specification.new do |spec|
  spec.name          = "agent_eval_planner"
  spec.version       = AgentEvalPlanner::VERSION
  spec.authors       = ["Saulo Filho"]
  spec.email         = ["saulofilho@users.noreply.github.com"]

  spec.summary       = "Generate agent guardrail eval plans, JSONL suites, and remediations"
  spec.description   = <<~DESC
    Ruby gem that analyzes an agent contract (system prompt, tools, policy gates)
    and generates a structured evaluation pipeline: action plan with SCOPE/INJECT/ROLE/PII/TOOL
    vectors, executable suite.jsonl with forbidden_tools filled, and remediations for prompt
    and policy gates. Parallel to security_pentest_planner, applied to LLM agents.
  DESC
  spec.homepage      = "https://saulofilho.github.io/agent-eval-planner/"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/saulofilho/agent-eval-planner"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    files = `git ls-files -z 2>/dev/null`.split("\x0")
    if files.empty?
      Dir.glob("{lib,exe}/**/*", File::FNM_DOTMATCH) +
        %w[README.md LICENSE.txt CHANGELOG.md]
    else
      files.reject { |file| file.start_with?("spec/", ".github/") || file.end_with?(".gem") }
    end
  end

  spec.bindir        = "exe"
  spec.executables   = ["agent-eval-planner"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
end
