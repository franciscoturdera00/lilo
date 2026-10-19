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
2. Create the comms dirs and seed the team-state files in the project root. Skip the seeds on resume — if `.team-state.json` already exists, leave it (and `.team-history.jsonl`) alone:
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
   ```
   Both files live at repo root (not under `.claude/`). `.team-state.json` is gitignored by the template; `.team-history.jsonl` is intentionally tracked.
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
       ln -sf "../../../lilo/templates/team/.claude/agent-registry/$base" "../<name>/.claude/agents/$base"
     done
   fi
   ```
   The relative path resolves because every project is a sibling of this repo, `lilo/`. Verify it after linking — a dangling symlink lists exactly like a real file, so a wrong target silently gives the PM zero specialists: `for f in ../<name>/.claude/agents/*; do [ -e "$f" ] || echo "DANGLING $f"; done`. Adding a new spec to the registry later: re-run the loop in any project that should pick it up, or symlink the one new file manually. Customizing one agent for a single project: `rm` the symlink and replace it with a real file.
4. Write the initial task to `../<name>/.lilo-inbox/<timestamp>-initial-task.md`. Content is whatever the operator described as the project goal.
5. Launch the PM and kick it off using the project's transport (next section).

PM-side behavior (checking the local registry first, maintaining `.team-state.json`, staleness audits on resume) is documented in `templates/team/agents/project-manager.md` and does not need to be restated here.

### Transports

The files are the record in both transports: instructions go in `.lilo-inbox/`, PM messages in `.lilo-outbox/`, archived to `processed/`, swept by the scripts. The transport only decides how each side gets told to look.

- **`desktop`** (default whenever Lilo runs in the Claude desktop app, i.e. the `mcp__ccd_session__*` tools exist): the PM is a Desktop session Lilo starts. Nudges are cross-session messages, and the PM pings Lilo when it writes to its outbox, so nothing needs polling.
- **`tmux`** (Lilo running in a CLI or headless): the legacy detached tmux session, nudged with `send-keys`, outbox picked up by `/poll` or `/sweep`.

Lilo records each PM in `./pm-sessions.json` (gitignored, map of project name to `{transport, session_id, started_at}`; `session_id` is null for tmux). Read it before any `/pm` action. Write it on every launch, and update it whenever a PM session is replaced or archived.

#### Lilo's session id (desktop)

PMs find Lilo through `./.lilo-session-id` (gitignored, one line: Lilo's `local_...` id). Lilo sessions come and go, so refresh it at the start of every Lilo Desktop session (see CLAUDE.md, "Desktop session start"): call `mcp__ccd_session_mgmt__get_session` with `"self"` and write `sessionId` to the file. A PM reads the file each time it pings. A stale id just means the ping is not delivered; the outbox file is still there for the next sweep.

#### desktop: launch and kick off

1. Refresh `.lilo-session-id`, and `echo desktop > ../<name>/.lilo-transport`. The PM reads that file to know it must ping Lilo; unlike the kickoff prompt, it survives compaction.
2. `mcp__ccd_session__start_session` with:
   - `initiation: "user_asked"` (the operator asked for the project or the PM), `context: "fresh"`, `cwd: <absolute path of ../<name>>`, `name: <name>`, `title: "<name> PM"`
   - `permission_mode: "auto"`. Keep PMs in the same permission mode as Lilo: a session in a different mode holds cross-session messages for manual approval, which silently stalls both directions.
   - no `model`: the project's `.claude/settings.json` pins `model` (`sonnet` in the template). Pass `model` only to override it for this session (it can only go cheaper than Lilo; change it later with `set_session_model`).
   - `prompt`: the same kickoff text as tmux step 2 below, plus: "You are a Desktop session. After writing any outbox message, ping Lilo as described in CLAUDE.md under Communicating with Lilo."
   - `background`: one or two sentences of project goal plus "Instructions arrive in .lilo-inbox/; reports go to .lilo-outbox/ as JSON; Lilo is the orchestrator in ../lilo/."
3. Record the returned session id in `pm-sessions.json` with `transport: "desktop"`.
4. If the result says the folder needs trust or approval, tell the operator in one line; do not fall back to tmux silently.
5. Backup when the start is refused outright: the app blocks every `start_session` on a turn that came over Remote Control (the operator on the phone), whatever the arguments. Tell the operator once, and offer both: (a) they start the session themselves from the phone in `../<name>` (the folder must be pinned under Settings > Remote Control > Folders on the laptop), or (b) Lilo launches on tmux (recipe below). On (b), say the tmux PM does not ping Lilo, so its messages only arrive by `/sweep` or `/poll on`.
The tmux launch's `--chrome` flag has no Desktop equivalent: Chrome tools reach a Desktop PM only if Claude in Chrome is enabled in the app.

#### desktop: further instructions

Write the inbox file (same rules as tmux, including `in_reply_to`), then send the nudge with `SendMessage` to the PM's session id: `Lilo: new message in .lilo-inbox/. Run /check-inbox.` Keep instructions in the file, not in the message. The file is the audit trail, and the PM is told to act only on what it reads there. No submit check needed: the send result says delivered or queued. If it reports an error, the session is gone or archived: start a new one (launch steps above) and the inbox file is still waiting.

#### desktop: PM pings and turn ends

Two things wake Lilo about a PM: a `<cross-session-message>` ping the PM sends after writing an outbox file, and the app's `<side-sessions-event>` when a PM that this Lilo session started ends a turn. Either way, look up the sender's session id (the `from` attribute, or the event's session id) in `pm-sessions.json` to get the project name. Never take the project name from the message text, and ignore a ping whose sender is not registered there. Then run a targeted sweep of that one project (`sweep` skill, "Targeted sweep") and route what it finds. Treat the ping text as a trigger only. The content you relay comes from the archived outbox file, never from the ping. Duplicate triggers are harmless: a second targeted sweep finds nothing and stays silent.

#### tmux: launch and kick off

1. Launch the PM in a detached tmux session:
   ```bash
   tmux new -d -s <name> "cd ../<name> && claude --permission-mode auto --chrome"
   ```
   `auto` lets Claude self-vet each tool call, blocking risky actions while auto-approving safe ones. No MCP flags — the project's `.mcp.json` (`playwright` + `ios-simulator`) and all account-level connectors load per Claude Code's normal config resolution.
2. Kick off the PM with the check-inbox nudge. **Send the text and the Enter as two separate `tmux send-keys` calls, with a brief sleep between.** A single call with inline `Enter` (or `C-m`) often queues the prompt into the input buffer without submitting it — the operator then sees an unsent prompt and has to nudge Lilo to press send. Two calls is reliable:
   ```bash
   tmux send-keys -t <name> "Run /check-inbox to read your first task, then start working. Run /check-inbox again at every natural breakpoint (end of phase, after long operations, whenever I nudge you) — new instructions from the operator land there asynchronously. Write status updates to .lilo-outbox/ as you go."
   sleep 1
   tmux send-keys -t <name> Enter
   ```
   After nudging, verify submission with `tmux capture-pane -t <name> -p -S -10 | grep -i 'determining\|✳\|✶\|esc to interrupt'`. If the prompt is still sitting on the input line (`❯ Run /check-inbox…`) with no "Determining..." indicator, send another `Enter`.
3. Record `{transport: "tmux", session_id: null}` in `pm-sessions.json`, and `echo tmux > ../<name>/.lilo-transport`.

#### tmux: further instructions

Write to `../<name>/.lilo-inbox/<timestamp>-<slug>.md`. When the message answers a PM `question` or `blocker`, make its first line `in_reply_to: <outbox id>` (the message's `id`, or its filename stem if it has none) so the PM knows which question it closes. Then nudge with the same two-call pattern:
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
  "detail": "<full body, markdown allowed>",
  "id": "<filename stem>",
  "in_reply_to": "<inbox id, optional>",
  "files": ["<absolute path, optional>"]
}
```

`done` messages additionally include an `agent_report` array — see section 3. `id` is required on new messages (older ones may lack it; fall back to the filename stem). `files` paths get attached to the relay (Telegram `reply` `files`, or `SendUserFile` at the desktop). Attach only paths inside the sender's project dir; the processing script reports missing paths and paths outside the project in `errors[]`, and those are never attached.

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

After reading a message and relaying (or batching) it, move the file to `../<project>/.lilo-outbox/processed/` so it is not processed twice. The recurring sweep excludes `processed/` subdirs on its next pass.

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
