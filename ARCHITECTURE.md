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
           │ Phase 0: Discovery & Recruitment
           │  1. claude mcp list → find available tools
           │  2. Read project CLAUDE.md → understand requirements
           │  3. Check .claude/agent-registry/ (curated specialists)
           │  4. Fall back to external marketplaces only if needed
           │  5. Recruit 3-5 tailored specialists → save to .claude/agents/
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
`.lilo-outbox/*.json`. Lilo sweeps those on a cron and relays to the
operator per the routing rules in `CLAUDE.md`.

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
        team/                # PM scaffold with .claude/agent-registry/
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

- **PM recruits its own team** — curated specialists in `.claude/agent-registry/`
  first, external marketplaces as fallback. Composition is tailored per project.
- **MCP tools inherited** — account-level MCPs (Notion, Figma, Gmail, etc.)
  are available to all sessions automatically
- **PM discovers MCPs before recruiting** — available tools inform team composition
- **PM refreshes MCPs each phase** — picks up newly added integrations
- **Crash recovery** — `.team-state.json` lets a PM rebuild team state on resume
- **Outbox relay** — PMs write JSON to `.lilo-outbox/`, Lilo sweeps and routes
  by `type`/`priority` to the operator

## Known limitations

- Agent teams can't be resumed directly — PM recreates team from `.team-state.json`
- One team per PM session, no nested teams
- The outbox sweep cron is session-only; Lilo re-registers it on every startup
