# Agent Registry

Local, curated specialist definitions used by the project-manager agent before falling back to external marketplaces.

## How the PM uses this

1. PM reads the project requirements and identifies the specialist roles needed
2. PM checks `.claude/agent-registry/` for matching roles — this directory, first
3. If a role has no local match, the PM searches external marketplaces (VoltAgent, wshobson, 0xfurai, everything-claude-code)
4. When a marketplace search yields a useful specialist, the PM MUST save it here for future reuse
5. PM copies the chosen agent files from the registry into `.claude/agents/` and briefs each specialist

## Roster

### Implementation (pick one per dispatch)

| Agent | Model | Use case |
|---|---|---|
| code | sonnet | General implementation. SCOPE IS LAW — touch only what the brief enumerates |
| code-architect | sonnet | Feature-level architectural design before implementation |
| frontend | sonnet | HTML/CSS/JS/React UI work |
| api-integrator | sonnet | External API clients |
| data-pipeline | sonnet | ETL, normalization |
| db-designer | sonnet | Schema design, migrations |
| scraper | sonnet | Playwright, data extraction |
| devops | sonnet | Deploy, Docker, cron, systemd |

### Review (fan out after implementation)

| Agent | Model | Use case |
|---|---|---|
| code-reviewer | sonnet | General code-quality and security review — default reviewer |
| typescript-reviewer | sonnet | TypeScript/JavaScript deep-dive review |
| python-reviewer | sonnet | Python deep-dive review |
| security-reviewer | opus | Pre-deploy security pass |
| design-critic | sonnet | Harsh UI/UX review |
| document-critic | sonnet | Prose/docs review |
| type-design-analyzer | sonnet | Type safety and invariant expression |
| silent-failure-hunter | sonnet | Finds swallowed errors, bad fallbacks, missing propagation |
| comment-analyzer | sonnet | Comment accuracy, rot, usefulness |
| pr-test-analyzer | sonnet | PR test coverage and quality |

### Cleanup and optimization

| Agent | Model | Use case |
|---|---|---|
| code-simplifier | sonnet | Clarity, consistency, preserve behavior |
| refactor-cleaner | sonnet | Dead code removal, duplicate consolidation |
| performance-optimizer | sonnet | Bottlenecks, bundle sizes, memory leaks |
| build-error-resolver | sonnet | Minimal-diff fixes to unblock build/type errors |

### Testing

| Agent | Model | Use case |
|---|---|---|
| test | sonnet | General unit + integration tests |
| tdd-guide | sonnet | Enforces write-tests-first methodology |
| e2e-runner | sonnet | End-to-end flows via Playwright + Chrome MCP for live debugging |
| ios-sim-driver | sonnet | iOS Simulator verification — boot/install/launch, UI assertions, screenshots |

### Documentation

| Agent | Model | Use case |
|---|---|---|
| docs | sonnet | READMEs, API docs, writing |
| doc-updater | haiku | Codemap generation and doc refresh |
| docs-lookup | sonnet | Library/framework doc lookup via Context7 MCP |

### Frontend-adjacent

| Agent | Model | Use case |
|---|---|---|
| a11y-architect | opus | WCAG 2.2 accessibility — Web and Native |
| seo-specialist | sonnet | Technical SEO audits, structured data, Core Web Vitals |

### Specialized

| Agent | Model | Use case |
|---|---|---|
| lora-prompt-builder | sonnet | Flux LoRA training captions, inference prompts, dataset audits |
| stitch-operator | sonnet | Drives the PicarX robot (Stitch) via the `picarx` MCP |

### PM infrastructure

| Agent | Model | Use case |
|---|---|---|
| team-historian | haiku | Read-only `.team-history.jsonl` queries — recall prior decisions/dispatches without bloating PM context |

## Tool scoping conventions

- **Read-only roles** (reviewers, auditors): Read, Glob, Grep [+ WebFetch if research needed]
- **Implementation roles**: Read, Write, Edit, Bash, Glob, Grep
- **Integration roles**: above + WebFetch
- **Never** grant Agent tool to a specialist — only the PM dispatches work

## Model tier conventions

- **opus**: critical reasoning (security review, architecture decisions, accessibility architecture)
- **sonnet**: everything else — implementation, testing, review, docs
- **haiku**: high-throughput, low-reasoning tasks (format, lint, simple lookups, doc generation)

## Refinement loop

The PM reports per-specialist performance in its `done` outbox message (`agent_report` field). Lilo aggregates these into `lilo/agent-feedback.jsonl` and refines registry definitions when an agent accumulates poor ratings. Do not hand-edit these files — let the feedback loop update them.

## Provenance

The following agents were imported from
<https://github.com/affaan-m/everything-claude-code> (ECC) on 2026-04-19,
individually reviewed for prompt-injection safety before import:

code-architect, code-reviewer, code-simplifier, refactor-cleaner,
performance-optimizer, build-error-resolver, type-design-analyzer,
silent-failure-hunter, comment-analyzer, pr-test-analyzer, typescript-reviewer,
python-reviewer, tdd-guide, e2e-runner, doc-updater, docs-lookup,
a11y-architect, seo-specialist.

If an ECC upstream agent is later updated in a way worth pulling, re-fetch
and re-review before overwriting. Never auto-sync.
