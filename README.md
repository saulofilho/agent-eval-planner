# agent_eval_planner

[![Gem Version](https://badge.fury.io/rb/agent_eval_planner.svg)](https://badge.fury.io/rb/agent_eval_planner)

**Site:** [saulofilho.github.io/agent-eval-planner](https://saulofilho.github.io/agent-eval-planner/)

Generates an **agent guardrail eval pipeline** from an agent contract (system prompt, tools, policy gates):

1. **Action plan** — SCOPE / INJECT / ROLE / PII / TOOL / HALLUC / EXFIL vectors  
2. **suite.jsonl** — executable cases with `forbidden_tools` filled  
3. **Remediations** — prompt / gate / evaluator quick wins  

Sibling of [`security_pentest_planner`](https://github.com/saulofilho/security-pentest-planner) — applied to LLM agents. Canonical smoke test: **carrot cake** (off-topic). If the agent answers, scope is not limited.

## Install

```bash
gem install agent_eval_planner
```

Or in the `Gemfile`:

```ruby
gem "agent_eval_planner"
```

## CLI

```bash
# Full pipeline → directory (plan + suite + remediations)
agent-eval-planner agent.md --tools search,fetch -t "Platform Team" -o ./out

# Validate suite (hard-fail on empty forbidden_tools / placeholders)
agent-eval-planner validate ./out/suite.jsonl --known-tools search,fetch

# Plan only to stdout
agent-eval-planner agent.md --plan-only --agent analytics
```

### Options

| Flag | Description |
|------|-------------|
| `-t, --team TEAM` | Team name in the title |
| `-a, --agent NAME` | `target_agent` name |
| `--tools LIST` | Comma-separated real tool names |
| `--scope TEXT` | Declared scope summary |
| `--harness NAME` | `generic` or `marketing-copilot` |
| `-o, --output PATH` | Output directory or single file |
| `--plan-only` / `--suite-only` / `--remediations-only` | Single artifact |

## Programmatic API

```ruby
require "agent_eval_planner"

result = AgentEvalPlanner.generate(
  input_path: "agent.md",
  team: "Platform Team",
  tools: %w[search fetch],
  agent_name: "default"
)

File.write("plano-de-acao-agent-eval.md", result.plan)
File.write("suite.jsonl", result.suite)
File.write("remediacoes.md", result.remediations)
```

## Publish to RubyGems.org (checklist)

### 1. One-time setup

1. Create an account at [rubygems.org](https://rubygems.org/sign_up).
2. Enable **MFA** (required — this gemspec sets `rubygems_mfa_required`).
3. Create an API key: **Settings → API keys** with permission to push gems.
4. Locally:

```bash
gem signin
# or:
mkdir -p ~/.gem && chmod 700 ~/.gem
echo "YOUR_API_KEY" > ~/.gem/credentials
chmod 600 ~/.gem/credentials
```

### 2. Before every release

```bash
cd agent-eval-planner
bundle install
bundle exec rspec
# bump lib/agent_eval_planner/version.rb + CHANGELOG.md
```

### 3. Build and push

```bash
gem build agent_eval_planner.gemspec
gem push agent_eval_planner-0.1.0.gem
```

Confirm at: https://rubygems.org/gems/agent_eval_planner

### 4. Tag the release (optional)

```bash
git tag v0.1.0
git push origin main --tags
```

> Never commit `*.gem` or `~/.gem/credentials`. Yank a bad release with `gem yank agent_eval_planner -v 0.1.0` only if necessary.

## GitHub Pages

This repo serves `docs/` as the project site.

1. Push to `https://github.com/saulofilho/agent-eval-planner`.
2. **Settings → Pages → Build and deployment**
3. Source: **Deploy from a branch**
4. Branch: `main` / folder: `/docs`
5. Site URL: https://saulofilho.github.io/agent-eval-planner/

## Development

```bash
git clone https://github.com/saulofilho/agent-eval-planner.git
cd agent-eval-planner
bundle install
bundle exec rspec
```

## License

MIT — see [LICENSE.txt](LICENSE.txt).
