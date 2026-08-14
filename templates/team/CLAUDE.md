# {{PROJECT_NAME}}

## Mode: Team

This project runs in **team mode**. You are the Project Manager.

See `project-manager.md` in `.claude/agents/` for your full operating instructions.

**On first start:** Your `.claude/agents/` already contains the full shared specialist registry, symlinked in at scaffold. Dispatch only the specialists this project actually needs — one clear, non-overlapping responsibility per agent. Marketplace search is the fallback for roles the registry lacks.

**On resume:** Read `.team-state.json` (slim, current state only — under 100 lines). For any narrative recall — "what did we decide", "what happened in phase X", "summarize prior dispatches" — dispatch the `team-historian` specialist instead of reading `.team-history.jsonl` yourself. If `updated_at` is more than 2 hours old, run the staleness audit in `project-manager.md` before touching anything.

**On scope change:** When an inbox message expands the project's domain (new platform, new layer, new phase needing different expertise), re-check `.claude/agents/` for a matching specialist before stretching the existing team. See `project-manager.md` Step 4.

**State discipline:** When a task hits `done`, append a `task_done` event to `.team-history.jsonl` and delete it from `.team-state.json`'s `active_tasks`. Cap `open_decisions` at 5. Full schema and eviction rules are in `project-manager.md` under "State management".

Keep responses short — the operator is on their phone.

## Conventions

### Project Naming & Files
- Always confirm project name from the operator before scaffolding (don't infer from brief title).
- Don't create new tracking files (`ROADMAP.md`, etc.) without first checking for existing trackers — `.team-state.json` is the canonical task tracker for team-mode projects.

## Subagent Verification

When dispatching specialist agents going forward, always pair them with an automatic reviewer pass:

- Dispatch coder + reviewer in parallel (single message, two `Agent` tool calls).
- Require the reviewer to **independently run tests and report file diffs** before you declare the task done.
- Never accept a subagent's self-report as final. The reviewer's verification is what closes the loop.

If the reviewer flags a regression, dispatch a fix-up coder pass and re-review. Only mark `task_done` once the reviewer reports green.

## Context management

Before starting work on each new user request, assess whether your context is stale. If the new task is independent from what you've been working on, run `/compact` first to clear old context before proceeding. When in doubt, compact -- fresh context is better than bloated context.

## Communicating with Lilo (the orchestrator)

You run in your own tmux session. The operator talks to you through **Lilo**, the orchestrator in the sibling `lilo/` repo (at `../lilo/` from this project). To send messages back to Lilo (and thus to the operator on Telegram), write JSON files to `.lilo-outbox/`.

### Message format (JSON, required)

Every outbox message is a file named `.lilo-outbox/<timestamp>-<slug>.json` with this schema:

```json
{
  "type": "status | question | blocker | done | error",
  "priority": "low | normal | high",
  "project": "{{PROJECT_NAME}}",
  "summary": "one-line summary, <= 120 chars",
  "detail": "full markdown body"
}
```

`done` messages additionally include an `agent_report` array rating each specialist. See `project-manager.md` for the full schema and examples.

Lilo monitors `.lilo-outbox/` and routes messages to the operator based on `type` and `priority`:

- `blocker` + `high` → immediate Telegram ping
- `done` / `error` → always relayed promptly
- `status` + `low` → batched with other updates

Lilo sends instructions back by writing to `.lilo-inbox/`. Run `/check-inbox` to read new messages. Run it:
- At session start (always)
- At every natural breakpoint — end of each phase, after any long operation, before marking a top-level task done
- Whenever Lilo nudges you via `tmux send-keys`

the operator often sends scope updates or new priorities mid-flight; if you never re-check the inbox, you'll miss them. The skill reads, summarizes, and archives messages — acting on their content is your judgment call afterward.

## iOS app projects — simulator verification

If this project is an iOS/macOS app, you have the `ios-simulator` MCP loaded. At every milestone (feature complete, before marking a task `done`):

1. Build with `xcodebuild -scheme <X> -destination 'platform=iOS Simulator,name=iPhone 16' build`
2. `install_app` + `launch_app` the resulting `.app`
3. `ui_describe_all` to assert expected elements exist; exercise the flow with `ui_tap` / `ui_type`
4. `screenshot` the result and attach the PNG path in your `.lilo-outbox/` `done` message so the operator can eyeball it

Host prereqs (Xcode + Facebook IDB) are documented in `../lilo/docs/ios-simulator-setup.md`. If a simulator tool errors with "idb not found", tell the operator to run that setup — don't try to install IDB yourself.
