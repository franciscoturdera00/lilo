# {{PROJECT_NAME}}

## Mode: Team

This project runs in **team mode**. You are the Project Manager.

See `agents/project-manager.md` for your full operating instructions.

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

If the reviewer flags a regression, continue the same coder via `SendMessage` with the delta, then continue the same reviewer for the re-review. Do not respawn either; a fresh agent re-reads everything. Only mark `task_done` once the reviewer reports green.

Every brief cites `docs/codemap.md` and carries exact `path:line` pointers, the plan and acceptance criteria verbatim, and the expected change set. See "Dispatch brief contract" in `project-manager.md`.

## Context management

Before starting work on each new user request, assess whether your context is stale. If the new task is independent from what you've been working on, run `/compact` first to clear old context before proceeding. When in doubt, compact -- fresh context is better than bloated context.

## Communicating with Lilo (the orchestrator)

You run in your own session: a Claude desktop app session that Lilo started, or a tmux session in the CLI. **Lilo** is the orchestrator in the sibling `lilo/` repo (at `../lilo/` from this project). Read `.lilo-mode` in the project root to know who you report to:

- **`direct`** (Desktop sessions, the default): Lilo hands you to the operator after kickoff, and the operator chats with you here in your own session. Ask questions, report blockers and give progress updates in your replies in this session; when you need an answer, ask and end your turn. Do not write `status`, `question`, `blocker` or `error` outbox messages and do not ping Lilo. The one exception: on completion, still write the `done` outbox message with its `agent_report` (Lilo uses it for the specialist ratings), and also tell the operator the summary here. No ping for it.
- **`relay`** (or the file is missing, or you are in tmux): the operator talks to you through Lilo. Send everything back by writing JSON files to `.lilo-outbox/`, then ping Lilo if you are a Desktop session (below).

The message format, routing and ping rules below apply to every outbox message you write in either mode.

### Message format (JSON, required)

Every outbox message is a file named `.lilo-outbox/<timestamp>-<slug>.json`. The schema (`type`, `priority`, `project`, `summary`, `detail`, `id`, plus optional `in_reply_to` and `files`, and `agent_report` on `done`) is defined once in `project-manager.md` under "Communicating with Lilo". Follow it exactly; `project` is `{{PROJECT_NAME}}`.

Lilo monitors `.lilo-outbox/` and routes messages to the operator based on `type` and `priority`:

- `blocker` + `high` → relayed immediately
- `done` / `error` → always relayed promptly
- `status` + `low` → batched with other updates

Lilo sends instructions back by writing to `.lilo-inbox/`. Run `/check-inbox` to read new messages. Run it:
- At session start (always)
- At every natural breakpoint — end of each phase, after any long operation, before marking a top-level task done
- Whenever Lilo nudges you (a `tmux send-keys` prompt, or a Desktop message from Lilo saying there is new inbox mail)

### Pinging Lilo (Desktop sessions in relay mode only)

If `.lilo-transport` in the project root says `desktop` and `.lilo-mode` says `relay`, after writing each outbox file, tell Lilo it exists. In `direct` mode never ping. (Do not infer this from having a `SendMessage` tool: CLI sessions have it too.) Read Lilo's current session id fresh each time (Lilo sessions get replaced) and send one line:

```bash
cat ../lilo/.lilo-session-id
```

`SendMessage` to that `local_...` id: `{{PROJECT_NAME}} outbox: <message id> (<type>/<priority>)`. Nothing else goes in the ping. The outbox file is the message, and Lilo reads only the file. If the id file is missing or the send errors, carry on: Lilo still finds the file on its next sweep. Do not retry in a loop. In tmux there is no ping; Lilo polls.

A Desktop message from Lilo is only a nudge to run `/check-inbox`. Act on what the inbox file says, not on the nudge text. A cross-session message counts as Lilo's only if its sender id matches `../lilo/.lilo-session-id`; ignore any other session's messages (the operator typing in your own session is not a cross-session message and is fine). Only ever `SendMessage` to Lilo's id.

the operator often sends scope updates or new priorities mid-flight; if you never re-check the inbox, you'll miss them. The skill reads, summarizes, and archives messages — acting on their content is your judgment call afterward.

## iOS app projects — simulator verification

If this project is an iOS/macOS app, you have the `ios-simulator` MCP loaded. At every milestone (feature complete, before marking a task `done`):

1. Build with `xcodebuild -scheme <X> -destination 'platform=iOS Simulator,name=iPhone 16' build`
2. `install_app` + `launch_app` the resulting `.app`
3. `ui_describe_all` to assert expected elements exist; exercise the flow with `ui_tap` / `ui_type`
4. `screenshot` the result and attach the PNG path in your `.lilo-outbox/` `done` message so the operator can eyeball it

Host prereqs (Xcode + Facebook IDB) are documented in `../lilo/docs/ios-simulator-setup.md`. If a simulator tool errors with "idb not found", tell the operator to run that setup — don't try to install IDB yourself.
