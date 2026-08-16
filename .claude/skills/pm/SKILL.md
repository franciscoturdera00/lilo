---
name: pm
description: PM control + project status. Default (no args) lists sibling projects and live tmux sessions. With an action (`start <name>`, `stop <name>`), operate on a specific PM tmux session. Use when the operator says "/pm", "status", "what's running", "/pm start X", "spin up the X PM", "/pm stop X", "kill the X PM session", or anything equivalent.
---

# pm

One skill for status + PM lifecycle. Replaces the old `project-status` skill.

## `/pm` (no args) — status

Run from the orchestrator repo root:

```bash
ls -1 .. | grep -Ev '^(orchestrator|tools|scratchpad|logs)$'
tmux ls 2>/dev/null || true
```

The first command lists project directories (excluding the orchestrator itself and infra dirs). The second shows active tmux sessions — typically team-mode PMs.

Report both lists concisely. If a project directory exists but has no tmux session, note that it is idle. If a session is active, mention its name.

## `/pm start <name>` — launch a PM session

Launches the PM for an already-scaffolded sibling project. PM state lives in `../<name>/.team-state.json` + `.team-history.jsonl`, so a fresh `claude` session resumes from where the previous one left off — no `--continue` needed.

1. Verify the project exists: `ls ../<name>/.claude/agents/` should not be empty. If the project was scaffolded but has no agents symlinks, fall back to the `team-ops` skill section 1 step 3 to populate them.
2. Bail out if the session is already running:
   ```bash
   tmux has-session -t <name> 2>/dev/null && echo "already running" || echo "ok to start"
   ```
3. Resolve the project's profile and assemble the launch flags from the matching overlay. **Do not hardcode flags here** — read them from the overlay's `launch.flags` so they live in one place (profiles currently share the same flags, but that can change):
   ```bash
   PROFILE=$(cat ../<name>/.team-profile 2>/dev/null || echo mvp)
   FLAGS=$(cat templates/overlays/$PROFILE/launch.flags)
   ```
   Legacy projects without `.team-profile` default to `mvp`; backfill the file by hand if that's wrong (`echo work > ../<name>/.team-profile`).
4. Launch + nudge using the **same pattern as `team-ops` section 1 steps 5–6**. Do not duplicate the recipe here — that file is the source of truth. Summary: detached `tmux new` with `claude $FLAGS` (using the `$FLAGS` you just resolved), then send `Run /check-inbox to read your first task...` text + Enter as **two separate** `tmux send-keys` calls with a `sleep 1` between them.
5. Verify submission with the same `tmux capture-pane | grep -i 'determining\|✳\|✶\|esc to interrupt'` check; resend Enter if needed.

Report back: "PM up in tmux session `<name>`. Attach with `tmux attach -t <name>`."

## `/pm stop <name>` — kill a PM tmux session

State persists in `.team-state.json` and `.team-history.jsonl`, so `/pm start` resumes cleanly. This is the right move when a PM is stuck, when the operator wants to clear stale conversation context, or just to free the slot.

1. Confirm with the operator before killing — PMs may have unsaved work in flight.
2. Check the session exists:
   ```bash
   tmux has-session -t <name> 2>/dev/null && echo "exists" || echo "no session"
   ```
3. Kill it:
   ```bash
   tmux kill-session -t <name>
   ```

Report back tersely.

## What this skill is NOT

- **Scaffolding a new project** — that's `new-project` + `team-ops`.
- **Sending an instruction to a running PM** — that's the inbox-nudge pattern documented in `team-ops` section 1 ("Sending further instructions"). Use that flow when the operator says "tell the X PM to do Y".
- **Tearing down a project entirely** — that's `nuke-project` (deletes files, confirms first).
