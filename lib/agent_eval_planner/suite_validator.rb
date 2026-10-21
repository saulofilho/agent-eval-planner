# frozen_string_literal: true

require "json"
require "set"

module AgentEvalPlanner
  # Hard-fail validator for legacy rows and native rows.
  class SuiteValidator
    PLACEHOLDER_RE = /\{\{[^{}]+\}\}/
    ID_RE = /\A[A-Za-z0-9][A-Za-z0-9._:-]*\z/
    GUARDRAIL_INTENTS = %w[
      out_of_scope_refusal
      prompt_injection
      role_escape
      prompt_exfiltration
      pii_probe
    ].freeze
    GUARDRAIL_TAGS = %w[scope injection role exfil pii guardrail].freeze
    DEFAULT_SUITES = %w[golden regression routing calibration production-sample].freeze
    SCHEMAS = %w[auto legacy native].freeze

    def initialize(path:, known_tools: [], bound_tools: nil, agent_has_no_tools: false,
                   target_components: nil, suites: nil, schema: "auto")
      @path = path
      @known_tools = clean_names(known_tools)
      @bound_tools = clean_names(bound_tools)
      @agent_has_no_tools = agent_has_no_tools
      @target_components = clean_names(target_components)
      @suites = clean_names(suites)
      @schema = schema
      @warnings = []
    end

    attr_reader :warnings

    def validate!
      errors = validate
      raise ValidationError, errors.join("\n") if errors.any?

      true
    end

    def validate
      raise InputError, "Arquivo não encontrado: #{path}" unless File.file?(path)

      raw = File.read(path, encoding: "UTF-8")
      @warnings = []
      errors = placeholder_errors(raw) + mode_errors
      run = {
        errors: errors,
        warnings: [],
        seen_ids: {},
        seen_schemas: Set.new,
        inventory: inventory,
        allowed_components: target_components.to_set,
        allowed_suites: (suites.any? ? suites : DEFAULT_SUITES).to_set,
        schema: SCHEMAS.include?(schema) ? schema : "auto"
      }

      raw.each_line.with_index(1) do |line, line_no|
        stripped = line.strip
        next if stripped.empty?

        row, load_errors = load_row(stripped, line_no)
        if row.nil?
          run[:errors].concat(load_errors)
          next
        end

        collect_row(run, row, line_no)
      end

      run[:errors].concat(mixed_schema_error(run[:seen_schemas]))
      @warnings = run[:warnings]
      run[:errors]
    end

    private

    attr_reader :path, :known_tools, :bound_tools, :agent_has_no_tools,
                :target_components, :suites, :schema

    def clean_names(names)
      Array(names).map(&:to_s).reject(&:empty?)
    end

    def guardrail_metadata?(metadata)
      return true if GUARDRAIL_INTENTS.include?(metadata["intent"].to_s)

      tags = Array(metadata["tags"]).map(&:to_s)
      (tags & GUARDRAIL_TAGS).any?
    end

    def placeholder_errors(raw)
      matches = raw.scan(PLACEHOLDER_RE).uniq.sort
      return [] if matches.empty?

      ["placeholders remaining (must be replaced before delivery): #{matches}"]
    end

    def mode_errors
      findings = []
      if agent_has_no_tools && (known_tools.any? || bound_tools.any?)
        findings << "pass either --agent-has-no-tools OR tool flags, not both"
      elsif !agent_has_no_tools && known_tools.empty? && bound_tools.empty?
        findings << "agent tool inventory required: pass --bound-tools a,b " \
                    "(and --known-tools when the product catalog is wider) " \
                    "or --agent-has-no-tools if the agent truly has no tools"
      elsif bound_tools.any? && known_tools.any? && !(bound_tools.to_set <= known_tools.to_set)
        extra = (bound_tools.to_set - known_tools.to_set).to_a.sort
        findings << "--bound-tools must be a subset of --known-tools; extra: #{extra}"
      end
      findings << "--schema must be auto, legacy, or native; got #{schema.inspect}" unless SCHEMAS.include?(schema)
      findings
    end

    def inventory
      known = (known_tools.any? ? known_tools : bound_tools).to_set
      bound = (bound_tools.any? ? bound_tools : known_tools).to_set
      separated = bound_tools.any? && known_tools.any? && bound_tools.to_set < known_tools.to_set
      {
        known: known,
        bound: bound,
        bound_explicit: separated,
        agent_has_no_tools: agent_has_no_tools
      }
    end

    def load_row(line, line_no)
      row = JSON.parse(line)
      return [nil, ["line #{line_no}: row must be a JSON object"]] unless row.is_a?(Hash)

      [row, []]
    rescue JSON::ParserError => e
      [nil, ["line #{line_no}: invalid JSON (#{e.message})"]]
    end

    def row_schema(row)
      native = row.key?("turns") || row.key?("target_component") || row.key?("suite")
      legacy = row.key?("input") || row.key?("expected")
      return "mixed" if native && legacy
      return "native" if native

      "legacy"
    end

    def collect_row(run, row, line_no)
      kind = row_schema(row)
      return if reject_schema(run, line_no, kind)

      row_id, id_errors = row_id_errors(row, line_no, run[:seen_ids])
      run[:errors].concat(id_errors)
      return if row_id.nil?

      append_shape_errors(run, row, row_id, kind)
      append_expectation_findings(run, row, row_id, kind)
    end

    def reject_schema(run, line_no, kind)
      if kind == "mixed"
        run[:errors] << "line #{line_no}: row mixes legacy input/expected with native turns"
        return true
      end
      if run[:schema] != "auto" && kind != run[:schema]
        run[:errors] << "line #{line_no}: expected --schema #{run[:schema]}, found #{kind}"
        return true
      end

      run[:seen_schemas] << kind
      false
    end

    def row_id_errors(row, line_no, seen_ids)
      row_id = row["id"]
      return [nil, ["line #{line_no}: missing id"]] if row_id.nil? || row_id.to_s.empty?

      row_id_str = row_id.to_s
      errors = []
      unless ID_RE.match?(row_id_str)
        errors << "line #{line_no}: id #{row_id.inspect} must match " \
                  "[A-Za-z0-9][A-Za-z0-9._:-]* (stable id)"
      end
      errors << "line #{line_no}: duplicate id #{row_id.inspect}" if seen_ids[row_id_str]
      seen_ids[row_id_str] = true
      [row_id_str, errors]
    end

    def append_shape_errors(run, row, row_id, kind)
      if kind == "native"
        run[:errors].concat(native_shape_errors(row, row_id, run))
      else
        run[:errors].concat(legacy_component_errors(row, row_id, run[:allowed_components]))
      end
    end

    def native_shape_errors(row, row_id, run)
      errors = []
      component = row["target_component"]
      if !component.is_a?(String) || component.empty?
        errors << "#{row_id}: native row requires target_component"
      elsif run[:allowed_components].any? && !run[:allowed_components].include?(component)
        errors << "#{row_id}: target_component #{component.inspect} not in " \
                  "--target-components #{run[:allowed_components].to_a.sort}"
      end

      suite_name = row["suite"]
      if !suite_name.is_a?(String) || suite_name.empty?
        errors << "#{row_id}: native row requires suite"
      elsif !run[:allowed_suites].include?(suite_name)
        errors << "#{row_id}: suite #{suite_name.inspect} not in #{run[:allowed_suites].to_a.sort}"
      end
      errors
    end

    def legacy_component_errors(row, row_id, allowed)
      return [] if allowed.empty?

      target_input = row["input"]
      return ["#{row_id}: missing input.target_agent"] unless target_input.is_a?(Hash)

      component = target_input["target_agent"]
      return [] if allowed.include?(component)

      ["#{row_id}: target_agent #{component.inspect} not in --target-components #{allowed.to_a.sort}"]
    end

    def append_expectation_findings(run, row, row_id, kind)
      blocks, block_errors = expectation_blocks(row, row_id, kind)
      run[:errors].concat(block_errors)
      blocks.each do |label, expectations, own_guardrail|
        found, warned = errors_for_expectations("#{row_id} #{label}", expectations, own_guardrail, run[:inventory])
        run[:errors].concat(found)
        run[:warnings].concat(warned)
      end
      run[:errors].concat(row_guardrail_gap(row, row_id, kind, blocks, run[:inventory]))
    end

    def expectation_blocks(row, row_id, kind)
      return legacy_block(row, row_id) if kind == "legacy"

      turns = row["turns"]
      return [[], ["#{row_id}: native row requires a non-empty turns list"]] unless turns.is_a?(Array) && turns.any?

      native_blocks(row_id, turns)
    end

    def legacy_block(row, row_id)
      expected = row["expected"]
      return [[], ["#{row_id}: missing expected object"]] unless expected.is_a?(Hash)

      metadata = row["metadata"].is_a?(Hash) ? row["metadata"] : {}
      own_guardrail = guardrail_metadata?(metadata) || expected["refusal"] == true
      [[["expected", expected, own_guardrail]], []]
    end

    def native_blocks(row_id, turns)
      blocks = []
      errors = []
      sequences = []
      turns.each_with_index do |turn, index|
        block, sequence, turn_errors = one_turn(row_id, index, turn)
        errors.concat(turn_errors)
        sequences << sequence unless sequence.nil?
        blocks << block unless block.nil?
      end
      if sequences.any? && sequences != (0...sequences.length).to_a
        errors << "#{row_id}: turn sequence must be contiguous from 0; got #{sequences}"
      end
      [blocks, errors]
    end

    def one_turn(row_id, index, turn)
      label = "turns[#{index}].expectations"
      return [nil, nil, ["#{row_id}: #{label} turn must be an object"]] unless turn.is_a?(Hash)

      errors = []
      sequence = turn["sequence"]
      recorded = sequence.is_a?(Integer) ? sequence : nil
      errors << "#{row_id}: turns[#{index}].sequence must be an int" if recorded.nil?
      expectations = turn["expectations"]
      unless expectations.is_a?(Hash)
        errors << "#{row_id}: missing #{label}"
        return [nil, recorded, errors]
      end

      turn_meta = turn["metadata"].is_a?(Hash) ? turn["metadata"] : {}
      own_guardrail = guardrail_metadata?(turn_meta) || expectations["refusal"] == true
      [[label, expectations, own_guardrail], recorded, errors]
    end

    def errors_for_expectations(where, expectations, guardrail, inventory)
      forbidden, errors = name_list(expectations, where, "forbidden_tools")
      expected, expected_errors = name_list(expectations, where, "expected_tools")
      errors.concat(expected_errors)
      return [errors, []] if forbidden.nil? || expected.nil?

      errors.concat(placeholder_names(where, "forbidden_tools", forbidden))
      errors.concat(placeholder_names(where, "expected_tools", expected))
      if inventory[:agent_has_no_tools]
        return [errors + findings_when_empty(where, forbidden, expected), []]
      end

      errors.concat(unknown_name_findings(where, forbidden, expected, inventory[:known]))
      bound_errors, warned = bound_findings(where, expectations, forbidden, expected, inventory, guardrail)
      [errors + bound_errors, warned]
    end

    def name_list(expectations, row_id, field)
      names = expectations[field]
      return [[], []] if names.nil? && field != "forbidden_tools"
      return [nil, ["#{row_id}: missing #{field}"]] if names.nil?
      return [nil, ["#{row_id}: #{field} must be a list"]] unless names.is_a?(Array)

      [names, []]
    end

    def placeholder_names(row_id, field, names)
      names.filter_map do |name|
        next unless PLACEHOLDER_RE.match?(name.to_s)

        "#{row_id}: placeholder left in #{field}: #{name.inspect}"
      end
    end

    def findings_when_empty(where, forbidden, expected)
      return [] if forbidden.empty? && expected.empty?

      [
        "#{where}: agent-has-no-tools but tools were listed " \
        "(forbidden=#{forbidden.inspect}, expected=#{expected.inspect})"
      ]
    end

    def unknown_name_findings(where, forbidden, expected, known)
      findings = []
      unknown_forbidden = forbidden.reject { |name| known.include?(name) }
      unknown_expected = expected.reject { |name| known.include?(name) }
      if unknown_forbidden.any?
        findings << "#{where}: forbidden_tools not in --known-tools: #{unknown_forbidden}"
      end
      if unknown_expected.any?
        findings << "#{where}: expected_tools not in --known-tools: #{unknown_expected}"
      end
      findings
    end

    def bound_findings(where, expectations, forbidden, expected, inventory, guardrail)
      errors = []
      outside_bound = expected.reject { |name| inventory[:bound].include?(name) }
      if outside_bound.any?
        errors << "#{where}: expected_tools not bound to this target: #{outside_bound}"
      end
      if expectations["refusal"] == true && expected.any?
        errors << "#{where}: refusal true cannot require expected_tools=#{expected.inspect}"
      end
      if guardrail && forbidden.none? { |name| inventory[:bound].include?(name) }
        errors << "#{where}: HARD FAIL - guardrail/refusal forbids no tool this " \
                  "target can call; suite cannot detect tool abuse"
      end

      warnings = []
      if inventory[:bound_explicit]
        unbound = forbidden.select { |name| inventory[:known].include?(name) && !inventory[:bound].include?(name) }
        if unbound.any?
          warnings << "#{where}: WARN - forbidden_tools names tools this target " \
                      "cannot call (assertion observes nothing): #{unbound}"
        end
      end
      [errors, warnings]
    end

    def forbids_bound?(expectations, bound)
      listed = expectations["forbidden_tools"]
      return false unless listed.is_a?(Array)

      listed.any? { |name| bound.include?(name) }
    end

    def row_guardrail_gap(row, row_id, kind, blocks, inventory)
      return [] unless kind == "native"
      return [] if inventory[:agent_has_no_tools]

      metadata = row["metadata"].is_a?(Hash) ? row["metadata"] : {}
      return [] unless guardrail_metadata?(metadata)
      return [] if blocks.any? { |(_, expectations, _)| forbids_bound?(expectations, inventory[:bound]) }

      [
        "#{row_id}: HARD FAIL - guardrail metadata requires at least one turn " \
        "to forbid a tool this target can call"
      ]
    end

    def mixed_schema_error(seen_schemas)
      return [] if seen_schemas.size < 2

      names = seen_schemas.to_a.sort.join(", ")
      [
        "mixed suite schemas in one file: #{names}. " \
        "Split legacy rows from native rows."
      ]
    end
  end
end
