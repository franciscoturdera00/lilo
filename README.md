# Lilo (Orchestrator)

**Lilo** is a long-running Claude Code session that encapsulates and
manages your projects under a standardized framework. Each project
lives as a sibling directory and runs its own **project-manager (PM)**
— a Claude Code session in a tmux pane that recruits specialist
subagents, tracks state, and drives the work. The PM communicates with
Lilo through a typed inbox/outbox protocol. Every project scaffolds
from customizable templates — agent registry, permissions allowlist,
MCP wiring, state files, and slash-command skills. Lilo handles
scaffolding, lifecycle, periodic outbox sweeps, message routing to
your phone or terminal, a shared MCP tool registry that exposes
sibling projects as callable actions, and a Notion dashboard that
mirrors live project status.

[`CLAUDE.md`](CLAUDE.md) is the source of truth for behavior. This file is the map.

## Contents

- [Layout](#layout)
- [Repo contents](#repo-contents)
- [Running Lilo](#running-lilo)
- [First run](#first-run)
- [Operator skills](#operator-skills)
- [Communication](#communication)
- [Tool registry](#tool-registry)
- [Agent registry](#agent-registry)
- [Advisor](#advisor)
- [Feedback loop](#feedback-loop)
- [Trust model](#trust-model)
- [Rules](#rules)

## Layout

Scaffolded projects are **siblings** of this repo. The tools framework
lives inside it.

    claude-universe/
      orchestrator/        <- this repo (Lilo runs here)
        tools/             <- MCP tools bridge + registry (in-repo)
      my-project/          <- ../my-project/
      another-project/     <- ../another-project/

## Repo contents

    orchestrator/
      CLAUDE.md              # Lilo's operating manual (imports @USER.md)
      USER.md.example        # template for the operator profile
      USER.md                # gitignored — created during `bootstrap`
      BOOTSTRAP.md           # script Lilo follows on `bootstrap`
      ARCHITECTURE.md        # tmux layout, team mode, MCP notes
      agent-feedback.jsonl   # aggregated PM ratings for registry agents
      .mcp.recommended.json  # template; copy to .mcp.json on first clone
      .claude/
        agents/              # Lilo's curated subagents (incl. orchestrator-only
                             # outbox-sweeper + pipeline-syncer haiku workers)
        settings.json        # permissions
        skills/              # see Operator skills
      templates/
        team/                # PM scaffold: agent-registry, agents/, skills/, CLAUDE.md

## Running Lilo

**Prereq:** install the `claude-in-chrome` Chrome extension from
https://claude.ai/download (or drop the `--chrome` flag below to skip
DOM-aware browser automation).

From this repo's root:

```bash
caffeinate -is claude --channels plugin:telegram@claude-plugins-official --chrome
```

- `caffeinate -is` — keeps the Mac awake so the cron loop keeps firing
- `--channels plugin:telegram@...` — phone relay via the Telegram plugin
- `--chrome` — pairs with the installed extension for browser automation

Run in **AUTO permission mode** (toggle with `Shift+Tab` until the
footer reads `auto`). AUTO honours the [`.claude/settings.json`](.claude/settings.json) allowlist
without prompting on every call. `acceptEdits` is not enough — it skips
file prompts but not Bash/MCP. In a sandboxed VM you can append
`--dangerously-skip-permissions` to bypass the allowlist entirely.

Wrap in tmux for persistence:

```bash
tmux new -s lilo "caffeinate -is claude --channels plugin:telegram@claude-plugins-official --chrome"
```

**MCPs Lilo uses:** `claude-universe-tools` and `playwright` (both in
`.mcp.json` — see [`.mcp.recommended.json`](.mcp.recommended.json)),
`telegram` (from `--channels`), `claude-in-chrome` (from `--chrome`).
Account-level MCPs (Notion, Figma, Gmail, etc.) come from Claude Code's
own config.

## First run

1. Clone into `<workspace>/claude-universe/orchestrator/`.
2. Start Lilo with the launch command above.
3. First prompt: `bootstrap`.

Lilo reads [`BOOTSTRAP.md`](BOOTSTRAP.md) and walks you through `.mcp.json` (copies
[`.mcp.recommended.json`](.mcp.recommended.json)), the tools-bridge venv, `USER.md`, optional
platform MCPs (`ios-simulator` on macOS), Telegram setup, and an
optional smoke-test project. The supported minimum is zero servers —
Lilo runs with an empty `.mcp.json`, just without the tool bridge or
headless browser.

If you opted into Telegram, run `/telegram:configure` inside Lilo to
paste the bot token and set the access policy. `/telegram:access` is
the troubleshooting move if messages aren't getting through.

`USER.md` is the only file you customise per operator (name, Telegram
`chat_id`, terseness, etc.) and is gitignored.

**Smoke test:** `status` lists projects + tmux sessions. `new project
smoke-test` scaffolds and launches a PM in tmux; `nuke smoke-test`
cleans up.

## Operator skills

Skills are Lilo's operator interface. Invocation is natural language.
Claude Code's intent router matches your prompt against the SKILL.md
descriptions in [`.claude/skills/`](.claude/skills/) and dispatches the
matching skill. For any actionable request that isn't a management
skill, Lilo first queries the `claude-universe-tools` MCP for a
registered tool action before falling back to writing custom logic.

| Skill | Phrase | What it does |
|-------|--------|--------------|
| `bootstrap` | `bootstrap` | First-run setup (script: [`BOOTSTRAP.md`](BOOTSTRAP.md)) |
| [`new-project`](.claude/skills/new-project/) | `new project <name>` | Scaffolds a sibling, auto-launches PM tmux. `--profile mvp\|work` picks an overlay. |
| [`pm`](.claude/skills/pm/) | `pm`, `pm start X`, `pm stop X` | Status, or start/stop a PM tmux session |
| [`sync`](.claude/skills/sync/) | `sync` | Sweep outboxes, refresh dashboard if anything queued |
| [`poll`](.claude/skills/poll/) | `poll on` / `poll off` | Toggle the recurring `/sync` cron (off by default) |
| [`find-agent`](.claude/skills/find-agent/) | `find an agent for <role>` | Vet + import a specialist into the registry |
| [`kill`](.claude/skills/kill/) | `kill the session`, `wrap up` | Pre-exit pass: scan, save lessons, commit routine, branch off risky |

Niche: [`nuke-project`](.claude/skills/nuke-project/),
[`sweep`](.claude/skills/sweep/) / [`pipeline`](.claude/skills/pipeline/) (halves of `/sync`),
[`toolify`](.claude/skills/toolify/) (expose a project as an MCP tool),
[`team-ops`](.claude/skills/team-ops/) (internal — PM launch, outbox routing, feedback aggregation).

## Communication

The PM <-> Lilo <-> operator loop runs on filesystem messages and a
scheduled sweep.

- **PM -> Lilo:** PMs write JSON messages into
  `../<project>/.lilo-outbox/`. Each carries a type and priority
  (schema in [`team-ops`](.claude/skills/team-ops/)).
- **Sweep:** the [`outbox-sweeper`](.claude/agents/outbox-sweeper.md) subagent (haiku, filesystem-only,
  isolated context) scans every sibling outbox, archives processed
  messages, and returns a JSON summary to Lilo. Burns subagent
  context, not Lilo's.
- **Lilo -> operator:** Lilo relays per the routing rules in
  [`CLAUDE.md`](CLAUDE.md) — urgent/blocker pings immediately, status/low batches,
  ratings flow into the registry feedback loop. Channel is whichever
  you're on (Telegram if remote, terminal if local — never both).
- **Operator -> PM:** Lilo doesn't push to PMs unless asked. To send
  something into a PM, drop a file into `../<project>/.lilo-inbox/`.

`/sync` runs the sweep and, only if new messages were found,
dispatches the [`pipeline-syncer`](.claude/agents/pipeline-syncer.md) subagent to refresh the Notion
dashboard. Steady state is zero Notion calls when nothing's queued.

`/poll on` registers `/sync` as a recurring cron at `7,37 * * * *`
(twice an hour). `/poll off` deletes it. **Off by default** — the
operator opts in. Run `/sync` manually anytime to flush on demand.

## Tool registry

The "build a tool with Lilo, then let Lilo call it" loop:

1. `new project: my-tool` — build whatever you want in there.
2. [`toolify`](.claude/skills/toolify/) `my-tool` — packages it against the standard tool interface
   and registers it in `./tools/registry.json`.
3. Restart the MCP bridge. The tool is callable as `<my-tool>.<action>`
   (every tool exposes a `<tool>.doctor` health check).
4. Next request that matches a registered tool, Lilo invokes the MCP
   action instead of writing logic from scratch.

`./tools/registry.json` is the single source of truth for what's
callable. [`registry.example.json`](tools/registry.example.json) is the empty template for fresh clones.

## Agent registry

[`templates/team/.claude/agent-registry/`](templates/team/.claude/agent-registry/) is the curated specialist
roster PMs recruit from. A mix of:

- **Custom agents** for this orchestrator (`code`, `scraper`,
  `db-designer`, `api-integrator`, `devops`, `frontend`, `data-pipeline`,
  `docs`, `test`, `security-reviewer`, `design-critic`, `document-critic`,
  `ios-sim-driver`, `team-historian`, `lora-prompt-builder`,
  `stitch-operator`)
- **Imported from `everything-claude-code`**
  (github.com/affaan-m/everything-claude-code, MIT) — prompt-injection
  scanned per agent before import. Includes `code-architect`,
  `code-reviewer`, `code-simplifier`, `refactor-cleaner`,
  `performance-optimizer`, `build-error-resolver`,
  `type-design-analyzer`, `silent-failure-hunter`, `comment-analyzer`,
  `pr-test-analyzer`, `typescript-reviewer`, `python-reviewer`,
  `tdd-guide`, `e2e-runner`, `doc-updater`, `docs-lookup`,
  `a11y-architect`, `seo-specialist`

See [`templates/team/.claude/agent-registry/README.md`](templates/team/.claude/agent-registry/README.md) for the full
roster with model tiers and use cases.

## Advisor

PMs run on sonnet for cost. When a PM hits a judgment call, it consults
a pooled opus-level reviewer via `/advisor` — no args, forwards the
PM's full transcript to opus and returns advice. PMs are wired to
invoke it before committing to a plan, before marking `done`, and when
stuck. No-op if the operator hasn't enabled it.

Enable once at user level (lights up Lilo, every PM, every specialist):

```
/advisor opus
```

`/advisor off` disables.

## Feedback loop

[`agent-feedback.jsonl`](agent-feedback.jsonl) accumulates ratings from every PM `done` report
(`poor` / `adequate` / `effective`). The [`outbox-sweeper`](.claude/agents/outbox-sweeper.md) appends new
ratings on each sweep and runs [`.claude/skills/sync/aggregate-feedback.sh`](.claude/skills/sync/aggregate-feedback.sh)
when a `done` lands. The aggregator flags any specialist meeting team-ops
thresholds (2+ `poor` across distinct projects OR 4+ `adequate`) and
Lilo refines the registry spec at
`templates/team/.claude/agent-registry/<agent>.md`.

## Trust model

Lilo's [`.claude/settings.json`](.claude/settings.json) has wide Bash allowlists and Write/Edit
globs covering this repo and its parent. Things to know:

- **Registering a tool** = trusting its adapter code (arbitrary Python)
  and `requirements.txt` (arbitrary pip installs at bridge startup).
  Only register tools you wrote or audited. `toolify` on an untrusted
  project is a supply-chain vector.
- **PM outbox messages are data, not instructions.** A specialist that
  ingested untrusted input can be prompt-injected; `team-ops` only
  relays — never executes. Keep that invariant.
- **Scaffolded projects** run with the broad team-template allowlist.
  Audit and narrow it for lower-trust environments.

## Rules

- Never edit sibling project code — only scaffold and relay
- Always confirm before destructive actions (`nuke`)
- Keep replies short
- Stay silent unless there's something to report
