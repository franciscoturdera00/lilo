# Agent Registry

Local, curated specialist definitions used by the project-manager agent before falling back to external marketplaces.

## How the PM uses this

1. PM reads the project requirements and identifies the specialist roles needed
2. The entire registry is already symlinked into the project's `.claude/agents/` at scaffold — every spec here is dispatchable directly, no copying. The team is the subset the PM records in `.team-state.json`, not everything on disk
3. If a role has no registry match, the PM searches external marketplaces (VoltAgent, wshobson, 0xfurai, everything-claude-code)
4. Marketplace finds are saved as a real file in the project's `.claude/agents/` and flagged to Lilo via the outbox — Lilo vets them (prompt-injection scan) into this shared registry; PMs never write into `../lilo/` themselves
5. To customize a spec for one project only: `rm` the symlink and replace it with a real file (editing through the symlink would change the shared registry for every project)

## Roster

### Implementation (pick one per dispatch)

| Agent | Use case |
|---|---|
| code | General implementation. SCOPE IS LAW — touch only what the brief enumerates |
| code-architect | Feature-level architectural design before implementation |
| frontend | HTML/CSS/JS/React UI work |
| api-integrator | External API clients |
| data-pipeline | ETL, normalization |
| db-designer | Schema design, migrations |
| scraper | Playwright, data extraction |
| devops | Deploy, Docker, cron, systemd |

### Review (fan out after implementation)

| Agent | Use case |
|---|---|
| code-reviewer | General code-quality and security review — default reviewer |
| typescript-reviewer | TypeScript/JavaScript deep-dive review |
| python-reviewer | Python deep-dive review |
| security-reviewer | Pre-deploy security pass |
| design-critic | Harsh UI/UX review |
| document-critic | Prose/docs review |
| type-design-analyzer | Type safety and invariant expression |
| silent-failure-hunter | Finds swallowed errors, bad fallbacks, missing propagation |
| comment-analyzer | Comment accuracy, rot, usefulness |
| pr-test-analyzer | PR test coverage and quality |

### Cleanup and optimization

| Agent | Use case |
|---|---|
| code-simplifier | Clarity, consistency, preserve behavior |
| refactor-cleaner | Dead code removal, duplicate consolidation |
| performance-optimizer | Bottlenecks, bundle sizes, memory leaks |
| build-error-resolver | Minimal-diff fixes to unblock build/type errors |

### Testing

| Agent | Use case |
|---|---|
| test | General unit + integration tests |
| tdd-guide | Enforces write-tests-first methodology |
| e2e-runner | End-to-end flows via Playwright + Chrome MCP for live debugging |
| ios-sim-driver | iOS Simulator verification — boot/install/launch, UI assertions, screenshots |

### Documentation

| Agent | Use case |
|---|---|
| docs | READMEs, API docs, writing |
| doc-updater | Codemap generation and doc refresh |
| docs-lookup | Library/framework doc lookup via Context7 MCP |

### Frontend-adjacent

| Agent | Use case |
|---|---|
| a11y-architect | WCAG 2.2 accessibility — Web and Native |
| seo-specialist | Technical SEO audits, structured data, Core Web Vitals |

### Specialized

| Agent | Use case |
|---|---|
| lora-prompt-builder | Flux LoRA training captions, inference prompts, dataset audits |
| stitch-operator | Drives the PicarX robot (Stitch) via the `picarx` MCP |

### PM infrastructure

| Agent | Use case |
|---|---|
| team-historian | Read-only `.team-history.jsonl` queries — recall prior decisions/dispatches without bloating PM context |

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
