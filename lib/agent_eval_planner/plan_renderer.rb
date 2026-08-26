# frozen_string_literal: true

module AgentEvalPlanner
  class PlanRenderer
    def initialize(analyzer:, vectors:, team: nil)
      @analyzer = analyzer
      @vectors = vectors
      @team = team || "TIME"
    end

    def render
      [
        header,
        introduction,
        eval_sections,
        summary_table,
        recommendations,
        out_of_scope
      ].compact.join("\n\n") + "\n"
    end

    private

    attr_reader :analyzer, :vectors, :team

    def header
      "# #{team} — Plano de Ação de Eval de Agente"
    end

    def introduction
      tools = analyzer.tools.empty? ? "_(nenhuma)_" : analyzer.tools.map { |t| "`#{t}`" }.join(", ")

      <<~MD.strip
        ## Introdução

        #{analyzer.introduction}

        **Agente(s) em escopo:** #{analyzer.agent_name}

        **Contrato analisado:** `#{analyzer.source_path || "inline"}`

        **Harness alvo:** #{analyzer.harness}

        **Escopo declarado (resumo):** #{analyzer.declared_scope}

        **Fora de escopo declarado:** #{analyzer.out_of_scope}

        **Tools / capabilities:** #{tools}
      MD
    end

    def eval_sections
      order = %w[SCOPE INJECT ROLE PII TOOL HALLUC EXFIL]
      grouped = vectors.group_by(&:category)
      order.filter_map do |cat|
        items = grouped[cat]
        next if items.nil? || items.empty?

        title = VectorCatalog::CATEGORY_TITLES[cat] || cat
        body = items.map { |v| render_vector(v) }.join("\n\n")
        "## EVAL — #{title}\n\n#{body}"
      end.join("\n\n---\n\n")
    end

    def render_vector(vector)
      <<~MD.strip
        #### #{vector.id} — #{vector.name}

        - **Severidade:** #{vector.severity}
        - **Objetivo:** #{vector.objective}
        - **Prompt de ataque:**
          ```text
          #{vector.attack_prompt}
          ```
        - **Validação esperada:** #{vector.expected_validation}
        - **Critério de falha:** #{vector.failure_criteria}
        - **Observação:** #{vector.notes.to_s.empty? ? "—" : vector.notes}
      MD
    end

    def summary_table
      rows = vectors.map do |v|
        "| #{v.id} | #{v.category} | #{v.severity} | #{v.name} | #{v.failure_criteria} |"
      end

      <<~MD.strip
        ## Tabela de resumo

        | ID | Categoria | Severidade | Vetor | Falha se |
        |----|-----------|------------|-------|----------|
        #{rows.join("\n")}

        **Prioridade de execução:** SCOPE → INJECT → ROLE → PII → TOOL → HALLUC → EXFIL
      MD
    end

    def recommendations
      tips = [
        "Rodar smoke pack (SCOPE-01, INJECT-01, ROLE-01) no harness antes de expandir a suite.",
        "Preencher `forbidden_tools` com as tools reais do agente — suite com lista vazia em refusal é falso verde.",
        "Preferir policy gate determinístico para off-topic previsível; o modelo sozinho não basta."
      ]
      tips << "Validar handoff entre specialists (SCOPE-04) — orchestrator detectado no contrato." if analyzer.multi_specialist?
      tips << "Cobrir grounding de métricas (HALLUC-01) com tool obrigatória ou recusa explícita." if analyzer.analytics_domain?

      body = tips.map.with_index(1) { |t, i| "#{i}. #{t}" }.join("\n")

      "## Recomendações imediatas\n\n#{body}"
    end

    def out_of_scope
      <<~MD.strip
        ## Fora do escopo deste plano

        - Pentest de API/infra (usar `security_pentest_planner`)
        - Journeys de UI / synthetics de browser
        - Modelo de ameaça corporativo completo
      MD
    end
  end
end
