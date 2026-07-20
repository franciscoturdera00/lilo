---
name: team-ops
description: Team-mode project coordination for Lilo — launching PM sessions on the `team` template, relaying PM outbox messages to the operator by type/priority, and aggregating specialist ratings into the registry-refinement loop. Use when scaffolding a team-template project, sweeping `../<project>/.lilo-outbox/*.json`, or processing `done` messages from PMs.
---

# team-ops

Lilo's playbook for projects. Covers the three coordination duties that are core to every scaffolded project and would otherwise clutter `CLAUDE.md`:

1. Launching a PM session after the scaffold is copied
2. Relaying PM messages from `.lilo-outbox/` to the operator
3. Aggregating agent feedback and refining the shared specialist registry

---

## 1. Launching the PM session

Runs after the `new-project` skill has already copied `templates/team/` into `../<name>/` and substituted `{{PROJECT_NAME}}`. Do these steps in order:

1. Ensure the scaffold included `.claude/agents/` and `CLAUDE.md`. The `cp -R templates/team/. ../<name>/` line in the scaffold recipe handles this; verify with `ls -la ../<name>/.claude/`. Note: agent specs live in the orchestrator's registry and are symlinked in step 3 — no per-project `agent-registry/` copy.
2. Create the comms dirs, seed the team-state files, and stamp the profile in the project root. Skip the seeds on resume — if `.team-state.json` already exists, leave it (and `.team-history.jsonl`, and `.team-profile`) alone:
   ```bash
   mkdir -p ../<name>/.lilo-inbox ../<name>/.lilo-outbox
   if [ ! -f ../<name>/.team-state.json ]; then
     NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
     jq -n --arg ts "$NOW" '{
       phase: "recruiting",
       status: "active",
       updated_at: $ts,
       completed_at: null,
       summary: "",
       team: [],
       active_tasks: [],
       open_decisions: [],
       context: ""
     }' > ../<name>/.team-state.json
     : > ../<name>/.team-history.jsonl
   fi
   [ -f ../<name>/.team-profile ] || echo "<profile>" > ../<name>/.team-profile
   ```
   All three files live at repo root (not under `.claude/`). `.team-state.json` is gitignored by the template; `.team-history.jsonl` and `.team-profile` are intentionally tracked. `.team-profile` records which overlay (`mvp` or `work`) the project was scaffolded with so `/pm start` can re-launch with the right flags.
3. **Symlink `.claude/agents/` to the orchestrator's registry — fresh scaffolds only.** Claude Code only indexes subagents that exist in `.claude/agents/` at session start. Use symlinks (not copies) so registry edits propagate to every project on next session start, with no per-project drift. **Skip this step on resume:** if `../<name>/.claude/agents/` already has real files (anything other than the template's `.gitkeep`), do nothing — agents/manual edits there are intentional.
   ```bash
   # The template ships a .gitkeep so the empty dir tracks under git.
   # Drop it on fresh scaffold; ls -A will then be empty unless someone
   # added real content (resume case), in which case skip the loop.
   rm -f ../<name>/.claude/agents/.gitkeep
   if [ -z "$(ls -A ../<name>/.claude/agents 2>/dev/null)" ]; then
     for f in templates/team/.claude/agent-registry/*.md; do
       base=$(basename "$f")
       [ "$base" = "README.md" ] && continue
       ln -sf "../../../orchestrator/templates/team/.claude/agent-registry/$base" "../<name>/.claude/agents/$base"
     done
   fi
   ```
   The relative path resolves because every project is a sibling of `orchestrator/`. Adding a new spec to the registry later: re-run the loop in any project that should pick it up, or symlink the one new file manually. Customizing one agent for a single project: `rm` the symlink and replace it with a real file.
4. Write the initial task to `../<name>/.lilo-inbox/<timestamp>-initial-task.md`. Content is whatever the operator described as the project goal.
5. Launch the PM in a detached tmux session. Read the CLI flags from the profile's overlay (`templates/overlays/<profile>/launch.flags`) so they live in one place. `<profile>` is whatever `new-project` resolved (default `mvp`):
   ```bash
   FLAGS=$(cat templates/overlays/<profile>/launch.flags)
   tmux new -d -s <name> "cd ../<name> && claude $FLAGS"
   ```
   Profile defaults today:
   - `mvp` → `--dangerously-skip-permissions --chrome --strict-mcp-config --mcp-config .mcp.json` — blocks account-level connectors so PM context stays slim; stdio MCPs come only from the project's `.mcp.json` (`playwright` + `ios-simulator`).
   - `work` → `--permission-mode auto --chrome --mcp-config .mcp.json` — drops `--strict-mcp-config` so work connectors (HubSpot/GitHub/ClickUp/Figma) load; the project's `settings.json` `permissions.deny` list blocks personal connectors (Telegram/Notion/Gmail/etc.) belt-and-suspenders. `auto` lets Claude self-vet permission prompts, blocking risky actions while auto-approving safe ones.

   `--chrome` is independent of MCP scoping and is unaffected by either profile.
6. Kick off the PM with the check-inbox nudge. **Send the text and the Enter as two separate `tmux send-keys` calls, with a brief sleep between.** A single call with inline `Enter` (or `C-m`) often queues the prompt into the input buffer without submitting it — the operator then sees an unsent prompt and has to nudge Lilo to press send. Two calls is reliable:
   ```bash
   tmux send-keys -t <name> "Run /check-inbox to read your first task, then start working. Run /check-inbox again at every natural breakpoint (end of phase, after long operations, whenever I nudge you) — new instructions from the operator land there asynchronously. Write status updates to .lilo-outbox/ as you go."
   sleep 1
   tmux send-keys -t <name> Enter
   ```
   After nudging, verify submission with `tmux capture-pane -t <name> -p -S -10 | grep -i 'determining\|✳\|✶\|esc to interrupt'`. If the prompt is still sitting on the input line (`❯ Run /check-inbox…`) with no "Determining..." indicator, send another `Enter`.

PM-side behavior (checking the local registry first, maintaining `.team-state.json`, staleness audits on resume) is documented in `templates/team/agents/project-manager.md` and does not need to be restated here.

**Sending further instructions** to a running PM: write to `../<name>/.lilo-inbox/<timestamp>-<slug>.md`, then nudge with the same two-call pattern:
```bash
tmux send-keys -t <name> "Run /check-inbox"
sleep 1
tmux send-keys -t <name> Enter
```
Verify afterward with the same capture-pane check above.

---

## 2. Outbox relay

PMs write JSON messages to `../<project>/.lilo-outbox/<timestamp>-<slug>.json`:

```json
{
  "type": "status | question | blocker | done | error",
  "priority": "low | normal | high",
  "project": "<project-name>",
  "summary": "<one-line, <= 120 chars>",
  "detail": "<full body, markdown allowed>"
}
```

`done` messages additionally include an `agent_report` array — see section 3.

### Routing rules

| Type      | Priority       | Action                                                      |
|-----------|----------------|-------------------------------------------------------------|
| `blocker` | `high`         | Relay to the operator on Telegram IMMEDIATELY, full detail |
| `error`   | any            | Relay promptly                                              |
| `done`    | any            | Relay promptly, then run section 3 (feedback aggregation)  |
| `question`| `high`/`normal`| Relay promptly                                              |
| `question`| `low`          | Batch with the next relevant relay                          |
| `status`  | `high`/`normal`| Relay                                                       |
| `status`  | `low`          | Batch; never wake the operator                              |

When relaying, lead with the `summary` line and include `project:` as context. Use the `detail` body verbatim — do not rewrite the PM's message.

### Housekeeping

After reading a message and relaying (or batching) it, move the file to `../<project>/.lilo-outbox/processed/` so it is not processed twice. The sweep cron (`7,37 * * * *`) excludes `processed/` subdirs on its next pass.

---

## 3. Agent feedback aggregation

Every `done` message includes an `agent_report` array rating each specialist on the build. Append each rating as its own line to `./agent-feedback.jsonl` at the orchestrator root, with the project name and an ISO timestamp:

```json
{"project": "<name>", "timestamp": "<ISO>", "agent": "code", "rating": "adequate", "notes": "Struggled with async patterns"}
```

### Canonical rating values

`rating` MUST be one of three strings — anything else is rejected on append (and the aggregator's normalizer will skip it):

- `poor` — agent failed the brief or shipped something the PM had to redo
- `adequate` — agent delivered, but with notable gaps the PM had to patch (scope drift, missed edge cases, etc.)
- `effective` — agent delivered cleanly; minor nits at most

PMs writing `agent_report` entries MUST use these strings. Numbers, "good"/"excellent"/"not-used", or other variants are not part of the schema. Aliases like `1`/`5` or `good` are still tolerated by the historical normalizer for backfill, but new entries should be canonical from the start.

### Refinement thresholds

`/sync` step 1.5 invokes `.claude/skills/sync/aggregate-feedback.sh` automatically on every tick (cron or manual). Ratings are **recency-weighted** by a half-life (default 45 days, override with `FEEDBACK_HALF_LIFE_DAYS`): a rating given today weighs 1.0, one a half-life ago weighs 0.5, and so on. Age is measured against `ref = max(newest rating, now)`, so a resolved historical cluster decays out of the flag instead of crying wolf every tick. The script reports any agent meeting either **weighted** threshold:

- **weighted `poor` >= 2.0** (recency-equivalent of "2 recent poor ratings"; a single project counts), OR
- **weighted `adequate` >= 4.0** (theme inspection happens at the LLM layer — the script just flags candidates)

Each flagged agent carries both the weighted score (`wpoor`/`wadequate`) and the raw counts + newest-first notes, so you can see whether a flag is recent-and-live or a fading tail. When a threshold is hit, refine `templates/team/.claude/agent-registry/<agent>.md` — update the system prompt, tool scope, or constraints to address the recurring issue. But first check `last_poor` and the note weights: if every poor predates the guardrail already in the spec, the fix is likely already in — say so rather than re-editing. Summarize what you found (refined, or verified-already-addressed) and tell the operator. **Do not wait to be asked** — the script flags candidates; Lilo follows up.
