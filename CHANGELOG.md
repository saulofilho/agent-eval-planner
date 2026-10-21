# Changelog

## [0.2.0] - 2026-10-21

### Added

- `--harness rd-copilot` emits the native row (`target_component`, `turns`, `suite=regression`, `metadata.vector_id`) that the rd-copilot harness loads
- Suite validator accepts that native shape and the legacy marketing-copilot row in the same gate: `--bound-tools`, `--schema`, `--target-components`, and warnings when `forbidden_tools` names a catalog tool the target cannot call

## [0.1.0] - 2026-08-26

### Added

- Contract analyzer for agent prompts / markdown / JSON
- Vector catalog with mandatory smoke pack (SCOPE / INJECT / ROLE) plus PII, TOOL, HALLUC, EXFIL
- Markdown plan, suite JSONL, and remediations renderers
- Suite validator (placeholders, empty `forbidden_tools`, unknown tools)
- CLI `agent-eval-planner` and `validate` subcommand
- Programmatic API `AgentEvalPlanner.generate`
- GitHub Pages site under `docs/`
