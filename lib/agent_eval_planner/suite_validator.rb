# frozen_string_literal: true

require "json"
require "set"

module AgentEvalPlanner
  # Hard-fail validator for suite JSONL (Ruby port of the skill script).
  class SuiteValidator
    PLACEHOLDER_RE = /\{\{[^{}]+\}\}/
    GUARDRAIL_INTENTS = %w[
      out_of_scope_refusal
      prompt_injection
      role_escape
      prompt_exfiltration
      pii_probe
    ].freeze
    GUARDRAIL_TAGS = %w[scope injection role exfil pii guardrail].freeze

    def initialize(path:, known_tools: [], agent_has_no_tools: false)
      @path = path
      @known_tools = Array(known_tools).map(&:to_s).reject(&:empty?)
      @agent_has_no_tools = agent_has_no_tools
    end

    def validate!
      errors = validate
      raise ValidationError, errors.join("\n") if errors.any?

      true
    end

    def validate
      raise InputError, "Arquivo não encontrado: #{path}" unless File.file?(path)

      raw = File.read(path, encoding: "UTF-8")
      errors = placeholder_errors(raw) + mode_errors
      known = known_tools.to_set
      seen_ids = {}

      raw.each_line.with_index(1) do |line, line_no|
        stripped = line.strip
        next if stripped.empty?

        row, load_errors = load_row(stripped, line_no)
        if row.nil?
          errors.concat(load_errors)
          next
        end

        row_id, id_errors = row_id_errors(row, line_no, seen_ids)
        errors.concat(id_errors)
        next if row_id.nil?

        errors.concat(errors_for_row(row, row_id, known: known))
      end

      errors
    end

    private

    attr_reader :path, :known_tools, :agent_has_no_tools

    def placeholder_errors(raw)
      matches = raw.scan(PLACEHOLDER_RE).uniq
      return [] if matches.empty?

      ["placeholders remaining (must be replaced before delivery): #{matches.sort}"]
    end

    def mode_errors
      if agent_has_no_tools && known_tools.any?
        return ["pass either --agent-has-no-tools OR --known-tools, not both"]
      end
      if !agent_has_no_tools && known_tools.empty?
        return [
          "agent tool inventory required: pass --known-tools a,b,c " \
          "or --agent-has-no-tools if the agent truly has no tools"
        ]
      end

      []
    end

    def load_row(line, line_no)
      row = JSON.parse(line)
      return [nil, ["line #{line_no}: row must be a JSON object"]] unless row.is_a?(Hash)

      [row, []]
    rescue JSON::ParserError => e
      [nil, ["line #{line_no}: invalid JSON (#{e.message})"]]
    end

    def row_id_errors(row, line_no, seen_ids)
      row_id = row["id"]
      return [nil, ["line #{line_no}: missing id"]] if row_id.nil? || row_id.to_s.empty?

      row_id_str = row_id.to_s
      errors = []
      errors << "line #{line_no}: duplicate id #{row_id.inspect}" if seen_ids[row_id_str]
      seen_ids[row_id_str] = true
      [row_id_str, errors]
    end

    def errors_for_row(row, row_id, known:)
      forbidden, errors = forbidden_tools(row, row_id)
      return errors if forbidden.nil?

      return errors + no_tools_mode_errors(row_id, forbidden) if agent_has_no_tools

      errors +
        empty_guardrail_forbidden_errors(row, row_id, forbidden) +
        unknown_tools_errors(row_id, forbidden, known) +
        placeholder_tools_errors(row_id, forbidden)
    end

    def forbidden_tools(row, row_id)
      expected = row["expected"] || {}
      forbidden = expected["forbidden_tools"]
      return [nil, ["#{row_id}: missing expected.forbidden_tools"]] if forbidden.nil?
      return [nil, ["#{row_id}: forbidden_tools must be a list"]] unless forbidden.is_a?(Array)

      [forbidden, []]
    end

    def no_tools_mode_errors(row_id, forbidden)
      return [] if forbidden.empty?

      ["#{row_id}: agent-has-no-tools but forbidden_tools=#{forbidden.inspect}"]
    end

    def unknown_tools_errors(row_id, forbidden, known)
      unknown = forbidden.reject { |t| known.include?(t.to_s) }
      return [] if unknown.empty?

      ["#{row_id}: forbidden_tools not in --known-tools: #{unknown}"]
    end

    def placeholder_tools_errors(row_id, forbidden)
      forbidden.filter_map do |tool|
        next unless PLACEHOLDER_RE.match?(tool.to_s)

        "#{row_id}: placeholder left in forbidden_tools: #{tool.inspect}"
      end
    end

    def empty_guardrail_forbidden_errors(row, row_id, forbidden)
      return [] unless guardrail_row?(row)
      return [] unless forbidden.empty?

      [
        "#{row_id}: HARD FAIL — guardrail/refusal row has " \
        "forbidden_tools=[] while agent has tools; suite cannot " \
        "detect tool abuse (false sense of safety)"
      ]
    end

    def guardrail_row?(row)
      expected = row["expected"] || {}
      metadata = row["metadata"] || {}
      return true if expected["refusal"] == true
      return true if GUARDRAIL_INTENTS.include?(metadata["intent"].to_s)

      tags = Array(metadata["tags"]).map(&:to_s)
      (tags & GUARDRAIL_TAGS).any?
    end
  end
end
