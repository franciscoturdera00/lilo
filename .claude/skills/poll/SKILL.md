---
name: poll
description: Toggle the recurring sync loop, implemented as self-pacing ScheduleWakeup ticks. `/poll on` arms it (first tick ~10 minutes after activation, then adaptive 15-60 min). `/poll off` stops it. `/poll tick` is the wakeup firing — never typed by the operator. Use when the operator says "/poll on", "/poll off", "turn polling on", or "stop polling".
---

# poll

The loop runs on `ScheduleWakeup`, not cron: each tick runs `/sync`, then schedules the next tick with a delay adapted to what the sweep found. Quiet workspace backs off toward hourly; active PMs get checked sooner. Wakeups are session-only — polling dies with the session and must be re-armed with `/poll on` in a new one.

## `/poll on`

1. `CronList`; `CronDelete` any recurring job whose prompt is `/sync` (migration from the old cron implementation — normally none).
2. Arm the loop:
   ```
   ScheduleWakeup {delaySeconds: 600, prompt: "/poll tick", noop: false, reason: "polling armed; first sync in 10 min"}
   ```

Report: `Polling on. First /sync in ~10 min, then self-paced (15-60 min by activity). Session-only.`

If polling is already on, this just resets the pending tick to fire 10 minutes from now — that's fine, no special handling.

## `/poll tick`

Fired by the wakeup. Never invoked by the operator; if the operator types it anyway, treat it as `/poll on`.

1. Run the `/sync` skill (sweep, then pipeline only if the sweep found messages). Relay findings per its normal rules — surface only if something was found.
2. Pick the next delay:
   - Sweep found messages → `900` (PMs are active; check again sooner)
   - Sweep found nothing → previous delay + 900, capped at `3600` (back off while quiet). If the previous delay isn't in context (e.g. post-compact), use `1800`.
3. Re-arm:
   ```
   ScheduleWakeup {delaySeconds: <computed>, prompt: "/poll tick", noop: <true if the sweep found nothing AND the pipeline made no Notion calls, else false>, reason: "<what was found and why this cadence>"}
   ```

The re-arm in step 3 is what keeps polling alive — never skip it after a tick, even when `/sync` errored (report the error, re-arm at `1800`).

## `/poll off`

1. `ScheduleWakeup {stop: true}` — ends the loop and cancels the pending tick.
2. `CronList`; `CronDelete` any recurring job whose prompt is `/sync`, `/sweep`, or `/pipeline` (legacy cleanup — normally none).

Report: `Polling off.`
