---
name: pm
description: PM control + project status. Default (no args) lists sibling projects and live PM sessions (Desktop or tmux). With an action (`start <name>`, `stop <name>`), operate on a specific PM session. Use when the operator says "/pm", "status", "what's running", "/pm start X", "spin up the X PM", "/pm stop X", "kill the X PM session", or anything equivalent.
---

# pm

One skill for status + PM lifecycle. Replaces the old `project-status` skill.

Every PM has a transport (`desktop` or `tmux`), recorded in `./pm-sessions.json`. `team-ops` section 1 "Transports" defines both and owns the launch and nudge recipes. This skill only branches on them.

## `/pm` (no args) — status

Run from the orchestrator repo root:

```bash
ls -1 .. | grep -Ev '^(lilo|tools|scratchpad|logs|vault)$'
tmux ls 2>/dev/null || true
cat pm-sessions.json 2>/dev/null || echo '{}'
```

The first command lists project directories (excluding the lilo repo itself and the workspace infra dirs: tools, scratchpad, logs, vault). The second shows tmux PMs. For each `desktop` entry in `pm-sessions.json`, call `mcp__ccd_session_mgmt__get_session` with its `session_id` to see whether it is running, idle or archived.

Report concisely: running PMs (with transport), then idle projects. Link each Desktop PM as `[<name> PM](#<session_id>)` so the operator can open it.

## `/pm start <name>` — launch a PM session

Launches the PM for an already-scaffolded sibling project. PM state lives in `../<name>/.team-state.json` + `.team-history.jsonl`, so a fresh session resumes from where the previous one left off — no `--continue` needed.

1. Verify the project exists: `ls ../<name>/.claude/agents/` should not be empty. If the project was scaffolded but has no agents symlinks, fall back to the `team-ops` skill section 1 step 3 to populate them.
2. Bail out if the PM is already up. Check both, whatever `pm-sessions.json` says (tmux PMs from before the desktop transport have no entry):
   - `tmux has-session -t <name> 2>/dev/null && echo "already running" || echo "ok to start"`
   - `desktop` entry: `get_session` on its id. Not archived → it is up. Send it the `team-ops` desktop nudge instead of starting a second one, and report that.
3. Pick the transport: `desktop` when Lilo runs in the desktop app and the project's profile is not `work` (see `team-ops` "Transports"), else `tmux`. A project last run on tmux moves to desktop on its next start. That is fine, since state lives in files.
4. Resolve the project's profile (it still governs the project's `settings.json`, and the tmux flags):
   ```bash
   PROFILE=$(cat ../<name>/.team-profile 2>/dev/null || echo mvp)
   ```
   Legacy projects without `.team-profile` default to `mvp`; backfill the file by hand if that's wrong (`echo work > ../<name>/.team-profile`).
5. Launch + kick off with the matching `team-ops` recipe ("desktop: launch and kick off" or "tmux: launch and kick off"). Do not duplicate the recipe here.

Report back. Desktop: "PM up: [<name> PM](#<session_id>)." Tmux: "PM up in tmux session `<name>`. Attach with `tmux attach -t <name>`."

## `/pm stop <name>` — graceful shutdown of a PM session

State persists in `.team-state.json` and `.team-history.jsonl`, so `/pm start` resumes cleanly. This is the right move when a PM is stuck, when the operator wants to clear stale conversation context, or just to free the slot.

1. Confirm with the operator before stopping — PMs may have unsaved work in flight. (An explicit "/pm stop X" or "restart the X PM" from the operator IS the confirmation.)
2. Trigger the PM's own `/kill` routine so it wraps up cleanly (saves lessons, commits routine work) before the session ends.

**desktop:**

3. Write `../<name>/.lilo-inbox/<timestamp>-kill.md` saying "Wrap up now: run your /kill skill, then end your turn." Then send the normal desktop nudge (`team-ops`) with `notify_when_idle: true`. Instructions travel in the inbox file, never in the nudge text. If the send errors (session already gone), skip to step 5.
4. Wait for the idle notice (or the `<side-sessions-event>` for its turn end). Do not poll. If the notice says the subscription expired, check the session with `get_session` and tell the operator rather than archiving mid-commit.
5. `mcp__ccd_session_mgmt__archive_session` on the id (reversible from the sidebar), then remove the entry from `pm-sessions.json`.

**tmux:**

3. Send `/kill` as text + Enter, two separate `send-keys` calls, same as every other nudge:
   ```bash
   tmux send-keys -t <name> "/kill"
   sleep 1
   tmux send-keys -t <name> Enter
   ```
4. Wait for the `/kill` routine to finish — poll `tmux capture-pane -t <name> -p` every ~10s until `esc to interrupt` is gone from the pane. Grep for that string ONLY — the spinner glyphs (✳ ✶ ✻) persist in scrollback on finished status lines ("✻ Worked for 1m") and false-positive forever. Give it up to ~3 minutes; if still busy, eyeball the pane tail (the PM usually ends with "Safe to kill") before deciding, and tell the operator rather than yanking the session mid-commit.
5. Then kill the tmux session and drop the `pm-sessions.json` entry:
   ```bash
   tmux kill-session -t <name>
   ```
   If the pane never accepted the `/kill` (e.g. claude already exited), just kill the session directly.

Report back tersely.

## What this skill is NOT

- **Scaffolding a new project** — that's `new-project` + `team-ops`.
- **Sending an instruction to a running PM** — that's the inbox-nudge pattern documented in `team-ops` section 1 ("desktop: further instructions" or "tmux: further instructions"). Use that flow when the operator says "tell the X PM to do Y".
- **Tearing down a project entirely** — that's `nuke-project` (deletes files, confirms first).
