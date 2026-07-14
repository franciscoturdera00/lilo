---
name: sweep
description: Outbox sweep — dispatches the `outbox-sweeper` subagent to find new PM messages across every sibling project, archive them, and roll up agent feedback. The subagent returns a JSON summary; Lilo only relays to the operator if anything was found. Use when the operator says "/sweep" or "sweep now".
---

# sweep

Thin dispatcher. The real work happens in the `outbox-sweeper` subagent — Lilo only spends context when the sweep finds something.

## Step 1 — Dispatch the sweeper in the background

Always dispatch with `run_in_background: true` so the cron tick (or manual fire) does not block Lilo's main loop. You will be notified when the subagent completes, and you handle Step 2 then.

```
Agent({
  subagent_type: "outbox-sweeper",
  description: "Outbox sweep",
  prompt: "Sweep all sibling outboxes. Return the JSON summary.",
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

The sweeper archives via `./scripts/sweep-outbox.sh`, which writes every archived path to `/tmp/lilo-sweep-manifest.txt`. That file — not the subagent's JSON — is the ground truth for what got swept.

```bash
wc -l < /tmp/lilo-sweep-manifest.txt
```

Compare to `len(messages)`. **If they disagree, the sweeper dropped messages.** Read the missing paths yourself (they are archived, not lost) and relay them. Do not present the sweep as clean.

This is not paranoia about a hypothetical. On 2026-07-14 a sweep archived 42 starwood messages and returned 3. Feedback for all 42 was written to the log; 39 were never relayed. Nothing errored, the outbox was empty afterward, and every surface-level check said "clean sweep." The manifest is the only thing that would have caught it — so check it, every time, even when the returned list looks plausible.

## Step 3 — Surface only what matters

- **`messages` empty AND `errors` empty AND manifest count is 0:** stay completely silent. This is the common case (no operator-visible output).
- **`messages` non-empty:** route each per the routing table in `team-ops` SKILL section 2 (blocker/high → immediate; status/low → batch; etc.). Lead with `summary`, include `project:` as context, quote `detail` verbatim. If the operator is at the terminal, reply terse there; do not dual-post to Telegram.
- **Large backlog (say, >10 messages):** do not dump all of them. Lead with the count, group by project, pull out anything `blocker`/`question`/`error` or any open decision the operator still owes an answer on, and offer the rest on request. A backlog is normal after the cron has been off — relay it as a digest, but never silently truncate it into a "nothing new."
- **`feedback_aggregation.flagged_count > 0`:** for each flagged agent, read `templates/team/.claude/agent-registry/<agent>.md`, eyeball the adequate-notes themes, decide whether to refine the spec. Tell the operator what changed (or that you looked and nothing needed action).
- **`errors` non-empty:** surface briefly to the operator regardless of cron vs manual — broken telemetry should not be silent.

