# Orchestrator Architecture

## Layout

This repo is the orchestrator. Drop it into the directory where you
keep your Claude Code projects — every scaffolded project will sit as
a sibling. The tools framework lives inside this repo:

    <your-workspace>/
      lilo/                <- this repo (Lilo runs here)
        tools/             <- MCP tools bridge + registry (in-repo)
      <project-a>/         <- scaffolded project
      <project-b>/         <- scaffolded project

All internal references use paths relative to the lilo repo root.
Sibling projects are `../<name>/`; the tools framework is `./tools/`.

## Project mode

Every scaffolded project runs as a self-assembling PM + specialists team.
There is no single-session mode — `new-project` always copies the team
template and auto-launches the PM.

    Operator
      └→ PM (tmux session per project)
           │
           │ Phase 0: Discovery & Team Assembly
           │  1. claude mcp list → find available tools
           │  2. Read project CLAUDE.md → understand requirements
           │  3. .claude/agents/ already holds the full shared registry
           │     (symlinked at scaffold from lilo/templates/team/)
           │  4. Pick the specialists this project needs
           │  5. Fall back to external marketplaces only for missing roles
           │  6. Brief team on available MCP tools
           │
           │ Phase 1+: Execution
           │  PM routes work → specialists execute
           │  Low-confidence questions → surfaced to operator
           │  MCP tools refreshed each phase
           │
           ├→ specialist-1 (e.g. backend)
           ├→ specialist-2 (e.g. frontend)
           ├→ specialist-3 (e.g. reviewer)
           └→ .team-state.json (crash recovery)

PMs communicate back to Lilo asynchronously through
`.lilo-outbox/*.json`. Lilo sweeps those on the opt-in `/poll` cron
(or on-demand `/sync`) and relays to the operator per the routing
rules in `CLAUDE.md`.

## Repo contents

    lilo/
      CLAUDE.md              # Lilo's operating manual (imports @USER.md)
      USER.md.example        # committed operator-profile template
      USER.md                # gitignored — the actual operator profile
      ARCHITECTURE.md        # this file
      README.md              # repo map + setup notes
      agent-feedback.jsonl   # aggregated PM agent ratings
      .mcp.recommended.json  # template; copy to .mcp.json on first clone
      .claude/
        settings.json        # permissions allowlist
        skills/              # bootstrap, new-project, nuke-project, pm, team-ops, sweep, pipeline, sync, poll, toolify, find-agent, kill
      templates/
        team/                # PM scaffold; its .claude/agent-registry/ is the
                             # shared roster, symlinked into every project
      tools/                 # MCP bridge, framework lib, registry

## Commands

Intent matching lives in the skill descriptions (`.claude/skills/<name>/SKILL.md`). Natural-language triggers are handled directly — no slash prefix needed.

| Intent | Skill | What it does |
|--------|-------|-------------|
| `new project <name>` | `new-project` + `team-ops` | Scaffold team template and launch PM in tmux |
| `pm` / `status` | `pm` | List sibling projects and active tmux sessions |
| `pm start <name>` | `pm` | Launch the PM tmux session for an existing project |
| `pm stop <name>` | `pm` | Kill a PM tmux session (state persists, resume with `pm start`) |
| `nuke <name>` | `nuke-project` | Kill session and delete project files (confirms first) |
| `bootstrap` | `bootstrap` | First-run setup walkthrough |

## Key behaviors

- **PM inherits the full registry** — every spec in
  `templates/team/.claude/agent-registry/` is symlinked into the project's
  `.claude/agents/` at scaffold. The PM dispatches the subset the project
  needs; external marketplaces are the fallback for missing roles only.
- **MCP tools inherited** — account-level MCPs (Notion, Figma, Gmail, etc.)
  are available to all sessions automatically
- **PM discovers MCPs before planning** — available tools inform which
  specialists get dispatched
- **PM refreshes MCPs each phase** — picks up newly added integrations
- **Crash recovery** — `.team-state.json` lets a PM rebuild team state on resume
- **Outbox relay** — PMs write JSON to `.lilo-outbox/`, Lilo sweeps and routes
  by `type`/`priority` to the operator

## Known limitations

- Agent teams can't be resumed directly — PM recreates team from `.team-state.json`
- One team per PM session, no nested teams
- The outbox sweep cron is opt-in (`/poll on`) and session-scoped — re-enable
  it after a Lilo restart if you want polling back
