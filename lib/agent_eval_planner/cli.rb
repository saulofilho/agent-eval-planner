# frozen_string_literal: true

require "optparse"
require "fileutils"
require_relative "../agent_eval_planner"

module AgentEvalPlanner
  class CLI
    def self.run(argv = ARGV)
      new.run(argv)
    end

    def run(argv)
      argv = argv.dup
      return run_validate(argv[1..]) if argv.first == "validate"

      options = default_options
      parser = build_option_parser(options)
      parser.parse!(argv)

      input = argv.first
      abort parser.help if input.nil?

      result = AgentEvalPlanner.generate(
        input_path: input,
        team: options[:team],
        agent_name: options[:agent_name],
        tools: options[:tools],
        declared_scope: options[:declared_scope],
        out_of_scope: options[:out_of_scope],
        harness: options[:harness]
      )

      write_outputs(result, options)
    rescue Error => e
      warn "Erro: #{e.message}"
      exit 1
    end

    private

    def default_options
      {
        team: nil,
        agent_name: nil,
        tools: nil,
        declared_scope: nil,
        out_of_scope: nil,
        harness: "generic",
        output: nil,
        plan_only: false,
        suite_only: false,
        remediations_only: false
      }
    end

    def build_option_parser(options)
      OptionParser.new do |opts|
        opts.banner = <<~BANNER
          Usage: agent-eval-planner [options] <contract.md|prompt.txt|agent.json>
                 agent-eval-planner validate [options] <suite.jsonl>

          Gera plano de eval, suite JSONL e remediações a partir do contrato de um agente.

        BANNER

        opts.on("-t", "--team TEAM", "Nome do time no título") { |v| options[:team] = v }
        opts.on("-a", "--agent NAME", "Nome do target_agent") { |v| options[:agent_name] = v }
        opts.on("--tools LIST", "Tools conhecidas (vírgula)") { |v| options[:tools] = v }
        opts.on("--scope TEXT", "Escopo declarado (resumo)") { |v| options[:declared_scope] = v }
        opts.on("--out-of-scope TEXT", "Fora de escopo declarado") { |v| options[:out_of_scope] = v }
        opts.on("--harness NAME", "Harness alvo (generic|marketing-copilot)") { |v| options[:harness] = v }
        opts.on("-o", "--output PATH", "Arquivo .md ou diretório de saída") { |v| options[:output] = v }
        opts.on("--plan-only", "Gerar apenas o plano") { options[:plan_only] = true }
        opts.on("--suite-only", "Gerar apenas a suite JSONL") { options[:suite_only] = true }
        opts.on("--remediations-only", "Gerar apenas remediações") { options[:remediations_only] = true }
        opts.on("-v", "--version", "Exibe a versão") do
          puts "agent_eval_planner #{AgentEvalPlanner::VERSION}"
          exit
        end
        opts.on("-h", "--help", "Exibe esta ajuda") do
          puts opts
          exit
        end
      end
    end

    def write_outputs(result, options)
      if options[:output].nil?
        emit_stdout(result, options)
        return
      end

      path = options[:output]
      if File.directory?(path) || path.end_with?("/") || !File.extname(path).empty? && File.extname(path) != ".md" && File.extname(path) != ".jsonl"
        # treat as directory when no extension or explicit dir
      end

      if looks_like_directory?(path)
        FileUtils.mkdir_p(path)
        write_bundle(path, result, options)
      elsif options[:suite_only] || path.end_with?(".jsonl")
        File.write(path, result.suite)
        warn "Suite gerada em #{path}"
      else
        content = select_single(result, options) || result.plan
        File.write(path, content)
        warn "Artefato gerado em #{path}"
      end
    end

    def looks_like_directory?(path)
      File.directory?(path) || path.end_with?("/") || File.extname(path).empty?
    end

    def write_bundle(dir, result, options)
      unless options[:suite_only] || options[:remediations_only]
        plan_path = File.join(dir, "plano-de-acao-agent-eval.md")
        File.write(plan_path, result.plan)
        warn "Plano gerado em #{plan_path}"
      end
      unless options[:plan_only] || options[:remediations_only]
        suite_path = File.join(dir, "suite.jsonl")
        File.write(suite_path, result.suite)
        warn "Suite gerada em #{suite_path}"
      end
      return if options[:plan_only] || options[:suite_only]

      rem_path = File.join(dir, "remediacoes.md")
      File.write(rem_path, result.remediations)
      warn "Remediações geradas em #{rem_path}"
    end

    def emit_stdout(result, options)
      if options[:suite_only]
        print result.suite
      elsif options[:remediations_only]
        print result.remediations
      elsif options[:plan_only]
        print result.plan
      else
        print result.plan
        warn "\n# --- suite.jsonl ---\n"
        print result.suite
        warn "\n# --- remediacoes.md ---\n"
        print result.remediations
      end
    end

    def select_single(result, options)
      return result.suite if options[:suite_only]
      return result.remediations if options[:remediations_only]
      return result.plan if options[:plan_only]

      nil
    end

    def run_validate(argv)
      options = { known_tools: [], agent_has_no_tools: false }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: agent-eval-planner validate [options] <suite.jsonl>\n\n"
        opts.on("--known-tools LIST", "Tools reais (vírgula)") do |v|
          options[:known_tools] = v.split(",").map(&:strip).reject(&:empty?)
        end
        opts.on("--agent-has-no-tools", "Agente sem tools") { options[:agent_has_no_tools] = true }
        opts.on("-h", "--help", "Ajuda") do
          puts opts
          exit
        end
      end
      parser.parse!(argv)
      suite = argv.first
      abort parser.help if suite.nil?

      errors = SuiteValidator.new(
        path: suite,
        known_tools: options[:known_tools],
        agent_has_no_tools: options[:agent_has_no_tools]
      ).validate

      if errors.any?
        warn "INVALID: #{suite} (#{errors.size} error(s))"
        errors.each { |e| warn "  - #{e}" }
        exit 1
      end

      puts "OK: #{suite}"
    rescue Error => e
      warn "Erro: #{e.message}"
      exit 1
    end
  end
end

AgentEvalPlanner::CLI.run if $PROGRAM_NAME == __FILE__
