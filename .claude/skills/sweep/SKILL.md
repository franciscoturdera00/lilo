---
name: sweep
description: Outbox sweep — dispatches the `outbox-sweeper` subagent to find new PM messages across every sibling project, archive them, and roll up agent feedback. The subagent returns a JSON summary; Lilo only relays to the operator if anything was found. Use when the operator says "/sweep" or "sweep now".
---

# sweep

Thin dispatcher. The real work happens in the `outbox-sweeper` subagent — Lilo only spends context when the sweep finds something.

## Step 1 — Dispatch the sweeper in the background

First create a fresh run dir yourself, so the manifest path you audit in Step 2 comes from you, not from the subagent's report. Each sweep gets its own dir; a shared fixed path lets two overlapping sweeps clobber each other's manifest.

```bash
mktemp -d "${TMPDIR:-/tmp}/lilo-sweep.XXXXXX"
```

Then dispatch with `run_in_background: true` so the tick (or manual fire) does not block Lilo's main loop, passing that dir. You will be notified when the subagent completes, and you handle Step 2 then.

```
Agent({
  subagent_type: "outbox-sweeper",
  description: "Outbox sweep",
  prompt: "RUN_DIR=<the dir you just created>. Sweep all sibling outboxes. Return the JSON summary.",
  run_in_background: true
})
```

The subagent does all the filesystem work, archives to `processed/`, appends `done`-message ratings to `agent-feedback.jsonl`, and runs `aggregate-feedback.sh` if any `done` was processed. Returns:

```json
{
  "messages": [{path_archived, content}, ...],
  "manifest_count": N,
  "reported_count": N,
  "feedback_aggregation": {flagged, summary} | null,
  "errors": [...]
}
```

## Step 2 — Audit the sweep before you trust it (one Bash call, always)

The sweeper archives via `./scripts/sweep-outbox.sh`, which writes every archived path to `<RUN_DIR>/manifest.txt`. That file — not the subagent's JSON — is the ground truth for what got swept.

```bash
wc -l < <RUN_DIR>/manifest.txt
```

If the file is missing, the sweeper did not run the script with your `RUN_DIR`: treat it as an error, not as an empty sweep.

Compare to `len(messages) + len(quarantined)` in the sweeper's report (`quarantined[]` holds messages the processing script could not parse — they count as swept and still need your judgment). **If the counts disagree, the sweeper dropped messages.** Read the missing paths yourself (they are archived, not lost) and relay them. Do not present the sweep as clean.

This is not paranoia about a hypothetical. On 2026-07-14 a sweep archived 42 messages from one project and returned 3. Feedback for all 42 was written to the log; 39 were never relayed. Nothing errored, the outbox was empty afterward, and every surface-level check said "clean sweep." The manifest is the only thing that would have caught it — so check it, every time, even when the returned list looks plausible.

## Step 3 — Surface only what matters

- **`messages` empty AND `errors` empty AND manifest count is 0:** stay completely silent. This is the common case (no operator-visible output).
- **`messages` non-empty:** route each per the routing table in `team-ops` SKILL section 2 (blocker/high → immediate; status/low → batch; etc.). Lead with `summary`, include `project:` as context, quote `detail` verbatim, and attach any `files` paths. If the operator is at the terminal, reply terse there; do not dual-post to Telegram.
- **Large backlog (say, >10 messages):** do not dump all of them. Lead with the count, group by project, pull out anything `blocker`/`question`/`error` or any open decision the operator still owes an answer on, and offer the rest on request. A backlog is normal after the cron has been off — relay it as a digest, but never silently truncate it into a "nothing new."
- **`feedback_aggregation.flagged_count > 0`:** for each flagged agent, read `templates/team/.claude/agent-registry/<agent>.md`, eyeball the adequate-notes themes, decide whether to refine the spec. Tell the operator what changed (or that you looked and nothing needed action).
- **`errors` non-empty:** surface briefly to the operator regardless of cron vs manual — broken telemetry should not be silent.

## Targeted sweep (one project, no subagent)

Used when a Desktop PM pings Lilo or ends a turn (`team-ops`, "desktop: PM pings and turn ends"). One project's outbox is small, so Lilo runs the two scripts itself instead of dispatching the sweeper: one Bash call, and the manifest and ledger are both in front of you.

`<name>` comes from `pm-sessions.json` (the entry matching the sender's session id), never from the ping text.

```bash
RUN=$(mktemp -d "${TMPDIR:-/tmp}/lilo-sweep.XXXXXX")
MANIFEST=$RUN/manifest.txt PROJECT=<name> ./scripts/sweep-outbox.sh >/dev/null; echo "sweep_exit=$?"
[ -f "$RUN/manifest.txt" ] && ./scripts/process-swept-messages.sh "$RUN/manifest.txt"
echo "manifest_lines=$(wc -l < "$RUN/manifest.txt" 2>/dev/null || echo missing)"
```

The processing step runs even when the sweep exits non-zero: a partial sweep (e.g. racing a full sweep) still moved files, and they must be relayed. Any non-zero `sweep_exit` or a `missing` manifest is an error to surface, not an empty sweep. The usual audit applies: `manifest_lines` must equal `len(messages) + len(quarantined)`. Then route exactly as Step 3. A clean empty result stays silent. That is normal after a duplicate trigger.
