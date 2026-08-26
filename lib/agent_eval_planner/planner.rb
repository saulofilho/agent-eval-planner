# frozen_string_literal: true

module AgentEvalPlanner
  class Planner
    DEFAULT_OPTIONS = {
      team: nil,
      agent_name: nil,
      tools: nil,
      declared_scope: nil,
      out_of_scope: nil,
      harness: "generic"
    }.freeze

    Result = Struct.new(:plan, :suite, :remediations, :analyzer, :vectors, keyword_init: true)

    def initialize(input_path: nil, raw: nil, **options)
      @input_path = input_path
      @raw = raw
      @options = DEFAULT_OPTIONS.merge(options.compact)
    end

    def call
      analyzer = ContractAnalyzer.new(
        source_path: input_path,
        raw: raw,
        agent_name: options[:agent_name],
        tools: options[:tools],
        declared_scope: options[:declared_scope],
        out_of_scope: options[:out_of_scope],
        harness: options[:harness]
      )

      vectors = VectorCatalog.vectors_for(analyzer)
      raise InputError, "Nenhum vetor aplicável encontrado." if vectors.empty?

      Result.new(
        plan: PlanRenderer.new(analyzer: analyzer, vectors: vectors, team: options[:team]).render,
        suite: SuiteRenderer.new(analyzer: analyzer, vectors: vectors).render,
        remediations: RemediationRenderer.new(analyzer: analyzer, vectors: vectors, team: options[:team]).render,
        analyzer: analyzer,
        vectors: vectors
      )
    end

    private

    attr_reader :input_path, :raw, :options
  end
end
