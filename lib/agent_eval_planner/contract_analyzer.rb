# frozen_string_literal: true

require "json"
require "yaml"

module AgentEvalPlanner
  # Parses an agent contract file (markdown/text/JSON/YAML) into a structured profile.
  class ContractAnalyzer
    TOOL_LINE_RE = /
      ^\s*[-*]\s*`?([a-z][a-z0-9_]*)`?\s*$|
      ^\s*[-*]\s*tool[s]?\s*:\s*`?([a-z][a-z0-9_]*)`?|
      ^\s*`([a-z][a-z0-9_]*)`\s*[—(]\s*tool
    /ix

    TOOLS_INLINE_RE = /tools?\s*[:=]\s*\[([^\]]+)\]/i
    NAME_RE = /(?:agent(?:\s+name)?|specialist|target[_ ]?agent)\s*[:=]\s*["']?([A-Za-z0-9_\-./]+)["']?/i

    attr_reader :source_path, :raw, :agent_name, :tools, :declared_scope, :out_of_scope,
                :harness, :signals

    def initialize(
      source_path: nil,
      raw: nil,
      agent_name: nil,
      tools: nil,
      declared_scope: nil,
      out_of_scope: nil,
      harness: "generic"
    )
      @source_path = source_path
      @raw = raw || read_source!(source_path)
      @agent_name = agent_name || extract_agent_name || "default"
      @tools = normalize_tools(tools || extract_tools)
      @declared_scope = declared_scope || extract_scope_hint || "Escopo declarado no contrato do agente"
      @out_of_scope = out_of_scope || "Pedidos off-topic, assistente geral, conteúdo fora do domínio"
      @harness = harness || "generic"
      @signals = detect_signals
    end

    def has_tools?
      !tools.empty?
    end

    def multi_specialist?
      signals[:multi_specialist]
    end

    def analytics_domain?
      signals[:analytics]
    end

    def introduction
      parts = ["Agente **#{agent_name}**"]
      parts << "com #{tools.size} tool(s) no contrato" if has_tools?
      parts << "sem tools declaradas" unless has_tools?
      parts << "(harness: #{harness})"
      "#{parts.join(' ')}. Pipeline de eval de guardrails — paralelo do plano de pentest de API, aplicado a comportamento de LLM."
    end

    private

    def read_source!(path)
      raise InputError, "input_path é obrigatório quando raw não é informado." unless path
      raise InputError, "Arquivo não encontrado: #{path}" unless File.exist?(path)

      File.read(path, encoding: "UTF-8")
    end

    def normalize_tools(list)
      Array(list).flat_map { |item| item.to_s.split(",") }.map(&:strip).reject(&:empty?).uniq
    end

    def extract_tools
      from_structured = tools_from_structured
      return from_structured if from_structured.any?

      found = []
      raw.scan(TOOLS_INLINE_RE) do |match|
        found.concat(match.first.to_s.split(/[,\s]+/).map { |t| t.gsub(/["'`]/, "") })
      end
      raw.each_line do |line|
        m = line.match(TOOL_LINE_RE)
        next unless m

        found << (m[1] || m[2] || m[3])
      end
      found.map(&:strip).reject(&:empty?).uniq
    end

    def tools_from_structured
      data = parse_structured
      return [] unless data.is_a?(Hash)

      candidates = data["tools"] || data["agent_tools"] || data.dig("agent", "tools") || []
      Array(candidates).map(&:to_s)
    rescue StandardError
      []
    end

    def parse_structured
      return nil if raw.nil? || raw.strip.empty?
      return JSON.parse(raw) if source_path&.end_with?(".json") || raw.strip.start_with?("{")
      return YAML.safe_load(raw, permitted_classes: [Symbol]) if source_path&.match?(/\.(ya?ml)\z/i)

      nil
    end

    def extract_agent_name
      data = parse_structured
      if data.is_a?(Hash)
        name = data["agent_name"] || data["target_agent"] || data["name"] || data.dig("agent", "name")
        return name.to_s if name
      end
      m = raw.match(NAME_RE)
      m&.[](1)
    end

    def extract_scope_hint
      if (m = raw.match(/escopo(?:\s+declarado)?\s*[:=]\s*(.+)$/i))
        return m[1].strip
      end
      if (m = raw.match(/^#+\s*(.+)$/))
        return m[1].strip
      end

      nil
    end

    def detect_signals
      down = raw.downcase
      {
        has_tools: has_tools?,
        multi_specialist: down.match?(/specialist|orchestrator|handoff|multi[- ]?agent/),
        analytics: down.match?(/analytics|métrica|metrica|funnel|abertura|convers[aã]o|bigquery/),
        docs: down.match?(/docs?|help.?center|conhecimento|rag|retrieval/),
        mutable_tools: tools.any? { |t| t.match?(/ticket|delete|create|update|write|send|open_/i) },
        pii_surface: down.match?(/pii|cpf|email|tenant|cliente|customer/)
      }
    end
  end
end
