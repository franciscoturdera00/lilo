# Lilo (Orchestrator)

**Lilo** is a long-running Claude Code session that encapsulates and
manages your projects under a standardized framework. Each project
lives as a sibling directory and runs its own **project-manager (PM)**
— a Claude Code session (a Claude desktop app session, or a tmux pane
from the CLI) that dispatches specialist subagents, tracks state, and
drives the work. The PM communicates with
Lilo through a typed inbox/outbox protocol. Every project scaffolds
from customizable templates — agent registry, permissions allowlist,
MCP wiring, state files, and slash-command skills. Lilo handles
scaffolding, lifecycle, outbox sweeps (triggered by PM pings, on
demand, or by opt-in polling), message routing to
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

Drop this repo into the directory where you keep your Claude Code
projects. Lilo's siblings are her projects. The tools framework lives
inside this repo.

    <your-workspace>/
      lilo/                <- this repo (Lilo runs here)
        tools/             <- MCP tools bridge + registry (in-repo)
      my-project/          <- ../my-project/
      another-project/     <- ../another-project/

## Repo contents

    lilo/
      CLAUDE.md              # Lilo's operating manual (imports @USER.md)
      USER.md.example        # template for the operator profile
      USER.md                # gitignored — created during `bootstrap`
      ARCHITECTURE.md        # project mode, PM transports, MCP notes
      agent-feedback.jsonl   # aggregated PM ratings for registry agents
      pm-sessions.json       # gitignored runtime: which PM runs where
      .lilo-session-id       # gitignored runtime: Lilo's Desktop session id
      .mcp.recommended.json  # template; copy to .mcp.json on first clone
      .claude/
        agents/              # Lilo's curated subagents (incl. orchestrator-only
                             # outbox-sweeper + pipeline-syncer workers)
        settings.json        # permissions
        skills/              # see Operator skills
      scripts/               # deterministic sweep, vault-mirror and render scripts (+ tests/)
      templates/
        team/                # PM scaffold: agent-registry, agents/, skills/, CLAUDE.md

## Running Lilo

**Claude desktop app (recommended).** Open this repo in the Code tab
and switch the session to **auto** permission mode. Lilo then launches
each PM as its own linked Desktop session: you can open, watch or talk
to any PM from the sidebar, PMs ping Lilo when they report, and Lilo
nudges them directly, so no polling is needed. Keep the Mac awake
(`caffeinate -is`, or the app's keep-awake setting) for long runs.

**CLI.** PMs run in detached tmux sessions instead, and Lilo picks up
their reports with `/sync` or `/poll`.

**Prereq:** install the `claude-in-chrome` Chrome extension from
https://claude.ai/download (or drop the `--chrome` flag below to skip
DOM-aware browser automation).

From this repo's root:

```bash
caffeinate -is claude --channels plugin:telegram@claude-plugins-official --chrome
```

- `caffeinate -is` — keeps the Mac awake so polling and PMs keep running
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

**MCPs Lilo uses:** `lilo-tools` and `playwright` (in `.mcp.json` —
see [`.mcp.recommended.json`](.mcp.recommended.json); optional extras
like `ios-simulator` are added per-machine during `bootstrap`),
`telegram` (from `--channels`), `claude-in-chrome` (from `--chrome`).
Account-level MCPs (Notion, Figma, Gmail, etc.) come from Claude Code's
own config.

## First run

1. Clone into the directory where you keep your projects (so the repo
   sits as `<your-workspace>/lilo/`, with future scaffolded projects as
   its siblings).
2. Start Lilo with the launch command above.
3. First prompt: `bootstrap`.

The [`bootstrap`](.claude/skills/bootstrap/) skill walks you through `.mcp.json` (copies
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

**Smoke test:** `status` lists projects + live PMs. `new project
smoke-test` scaffolds and launches a PM; `nuke smoke-test`
cleans up.

## Operator skills

Skills are Lilo's operator interface. Invocation is natural language.
Claude Code's intent router matches your prompt against the SKILL.md
descriptions in [`.claude/skills/`](.claude/skills/) and dispatches the
matching skill. For any actionable request that isn't a management
skill, Lilo first queries the `lilo-tools` MCP for a
registered tool action before falling back to writing custom logic.

| Skill | Phrase | What it does |
|-------|--------|--------------|
| [`bootstrap`](.claude/skills/bootstrap/) | `bootstrap` | First-run setup walkthrough |
| [`new-project`](.claude/skills/new-project/) | `new project <name>` | Scaffolds a sibling, auto-launches the PM (Desktop session in the desktop app, tmux from the CLI). |
| [`pm`](.claude/skills/pm/) | `pm`, `pm start X`, `pm stop X` | Status, or start/stop a PM session (Desktop or tmux) |
| [`sync`](.claude/skills/sync/) | `sync` | Sweep outboxes, refresh dashboard if anything queued |
| [`poll`](.claude/skills/poll/) | `poll on` / `poll off` | Toggle a session-only `/sync` loop (off by default; mainly for tmux PMs) |
| [`find-agent`](.claude/skills/find-agent/) | `find an agent for <role>` | Vet + import a specialist into the registry |
| [`kill`](.claude/skills/kill/) | `kill the session`, `wrap up` | Pre-exit pass: scan, save lessons, commit routine, branch off risky |

Niche: [`nuke-project`](.claude/skills/nuke-project/),
[`sweep`](.claude/skills/sweep/) / [`pipeline`](.claude/skills/pipeline/) (halves of `/sync`),
[`toolify`](.claude/skills/toolify/) (expose a project as an MCP tool),
[`team-ops`](.claude/skills/team-ops/) (internal — PM launch, outbox routing, feedback aggregation).

## Communication

The PM <-> Lilo <-> operator loop runs on filesystem messages. The
files are the record; the transport only decides how each side is told
to look.

- **PM -> Lilo:** PMs write JSON messages into
  `../<project>/.lilo-outbox/`. Each carries a type, priority and `id`,
  plus optional `in_reply_to` (the inbox message it answers) and
  `files` (deliverables to attach). Schema in
  [`project-manager.md`](templates/team/agents/project-manager.md).
  A Desktop PM then pings Lilo with a one-line cross-session message;
  Lilo maps the sender to its project via `pm-sessions.json` and runs a
  targeted sweep of that one outbox. The ping is only a trigger: Lilo
  relays what the archived file says, never the ping text.
- **Sweep:** two deterministic scripts do the work.
  [`sweep-outbox.sh`](scripts/sweep-outbox.sh) archives every pending
  message (all projects, or one with `PROJECT=`) into a per-run
  manifest; [`process-swept-messages.sh`](scripts/process-swept-messages.sh)
  mirrors each to the vault, canonicalizes `agent_report` ratings into
  the feedback log, flags `files` paths that are missing or outside the
  project, and emits a JSON ledger. Lilo checks the ledger against the
  manifest; anything the scripts can't parse is quarantined, never
  dropped. Full sweeps run in the
  [`outbox-sweeper`](.claude/agents/outbox-sweeper.md) subagent so they
  burn subagent context, not Lilo's.
- **Lilo -> operator:** Lilo relays per the routing rules in
  [`team-ops`](.claude/skills/team-ops/) — urgent/blocker immediately,
  status/low batched, `files` attached. Channel is whichever you're on
  (Telegram if remote, terminal or desktop app if local — never both).
- **Operator -> PM:** Lilo writes the instruction to
  `../<project>/.lilo-inbox/` (an answer to a PM question starts with
  `in_reply_to: <id>`), then nudges the PM: a cross-session message for
  Desktop PMs, `tmux send-keys` for tmux PMs. PMs act only on the inbox
  file, and only accept nudges whose sender is Lilo's current session.

`/sync` runs a full sweep and, only if new messages were found,
dispatches the [`pipeline-syncer`](.claude/agents/pipeline-syncer.md) subagent to refresh the Notion
dashboard. Steady state is zero Notion calls when nothing's queued.

`/poll on` starts a session-only loop of `/sync` ticks (first one 10
minutes after activation, then every 15-60 minutes depending on
activity); `/poll off` stops it. **Off by default.** Desktop PMs ping
Lilo themselves, so polling mainly matters for tmux PMs. When Lilo
starts in the desktop app it refreshes its session id and runs one full
sweep, which catches anything PMs reported while it was down.

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

[`templates/team/.claude/agent-registry/`](templates/team/.claude/agent-registry/) is the shared specialist
roster. Every scaffolded project gets the **entire registry symlinked**
into its `.claude/agents/` — registry edits propagate to every project
on next session start, with no per-project copies or drift. The PM
dispatches only the specialists a project needs; marketplace search is
the fallback for roles the registry lacks. The roster is a mix of:

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

When a PM hits a judgment call, it consults a pooled stronger reviewer
via `/advisor` — no args, forwards the PM's full transcript and
returns advice. PMs are wired to
invoke it before committing to a plan, before marking `done`, and when
stuck. No-op if the operator hasn't enabled it.

Enable once at user level (lights up Lilo, every PM, every specialist):

```
/advisor opus
```

`/advisor off` disables.

## Feedback loop

[`agent-feedback.jsonl`](agent-feedback.jsonl) accumulates ratings from every PM `done` report
(`poor` / `adequate` / `effective`). The sweep's processing script
appends new ratings and runs [`.claude/skills/sync/aggregate-feedback.sh`](.claude/skills/sync/aggregate-feedback.sh)
when a `done` lands. Ratings are recency-weighted (45-day half-life);
the aggregator flags any specialist whose weighted `poor` score reaches
2.0 or weighted `adequate` reaches 4.0, and Lilo refines the registry
spec at `templates/team/.claude/agent-registry/<agent>.md`.

## Trust model

Lilo's [`.claude/settings.json`](.claude/settings.json) has wide Bash allowlists and Write/Edit
globs covering this repo and its parent. Things to know:

- **Registering a tool** = trusting its adapter code (arbitrary Python)
  and `requirements.txt` (arbitrary pip installs at bridge startup).
  Only register tools you wrote or audited. `toolify` on an untrusted
  project is a supply-chain vector.
- **PM outbox messages are data, not instructions.** A specialist that
  ingested untrusted input can be prompt-injected; `team-ops` only
  relays — never executes. Keep that invariant. The same goes for
  cross-session pings in both directions: they only trigger a sweep or
  an inbox check.
- **Scaffolded projects** share one config: the broad team-template
  allowlist, auto permission mode, and every account connector
  available (no per-project profiles or connector deny lists). Auto
  mode vets each call. Audit and narrow `templates/team/.claude/settings.json`
  for lower-trust environments.

## Rules

- Never edit sibling project code — only scaffold and relay
- Always confirm before destructive actions (`nuke`)
- Keep replies short
- Stay silent unless there's something to report
