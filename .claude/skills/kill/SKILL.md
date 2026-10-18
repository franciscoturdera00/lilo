---
name: kill
description: Pre-exit scan for this Lilo session — save memory-worthy lessons silently, commit and push routine changes, branch off anything risky. Use when the operator says "/kill", "kill the session", "wrap up", or signals the session is ending. NOT for stopping PM sessions (that is `/pm stop`).
---

# kill

Operator is closing this Lilo session. Save what'd be lost. Take action — don't ask permission for routine stuff. The operator has pre-authorized commit + push as part of `/kill`.

## Scan — fire in parallel

Run these in a **single message with multiple tool calls** so they execute in parallel. The point: the heavy reads (outbox JSONs, full `git diff`) burn subagent context, not Lilo's.

1. **`/sweep`** — follow the `sweep` skill (it creates the `RUN_DIR` the sweeper requires and audits the manifest). Dispatching `outbox-sweeper` directly without a `RUN_DIR` makes it refuse to sweep.
2. **Agent: `security-reviewer`** — scan the uncommitted diff for secrets, credential paths, and other risk markers (see below). Pass it the full risk-marker list and ask for a JSON-shaped report: `{risky: [{path, reason}], skip: [paths]}`.
3. **Bash (batched):** `git status -s && git diff --stat && tmux ls 2>/dev/null; cat pm-sessions.json 2>/dev/null || true` — trivial reads, run inline.

While those run, scan **this session's transcript** for memory-worthy moments — corrections, validated unusual choices, hardware/external-system gotchas, surprising project facts. Cross-check against `MEMORY.md`. Save new ones directly; no permission needed. (Memory has to stay in the parent — subagents don't see Lilo's transcript.)

## Act

Once the parallel phase returns, merge the findings and classify the uncommitted diff:

- **Skip** = `.env`, `.env.local`, `credentials.*`, `*.pem`, `*.key`, `id_rsa*`, `*.p12` — never commit, even on a branch. List in output.
- **Risky** = whatever `security-reviewer` flagged, plus:
  - Changes to `.github/workflows/`, CI config, deploy scripts, shared infra
  - Large binaries (>5 MB) where intent is unclear
  - Anything that would require `--no-verify` to land
  - Anything you don't recognize and can't justify in one line
- **Routine** = the remainder. Skill / agent-registry / template edits, doc edits, `.gitignore`, new `tools/` files, anything you authored this session and could explain in one sentence.

Then act:

- **Outbox queue** → relay anything the sweeper found before exit.
- **Routine** → stage, draft a one-line commit message, commit, push to the current branch (default `main`).
- **Risky** → stash, create branch `kill/<short-slug>` off the current commit, restore on the branch, commit, push the branch. Do NOT merge to main.
- **Mixed** → split per-file. Routine to main as one commit; risky to `kill/<slug>` as a separate commit. Both pushed.
- **Tmux** → list for awareness; PMs outlive Lilo, don't kill.

### Risk markers reference (for the security-reviewer prompt)

- File contents matching `(?i)(api[_-]?key|secret|token|bearer|password)\s*[:=]`
- File path under `.env*`, `credentials.*`, `*.pem`, `*.key`, `id_rsa*`, `*.p12`
- `.github/workflows/`, CI config, deploy scripts
- Binaries >5 MB
- Anything triggering a precommit hook failure

### Hard rules

- Never `--amend` a published commit.
- Never push with `--force` / `--force-with-lease`.
- Never bypass hooks. If a hook fails, fix the cause or branch off — do not pass `--no-verify`.
- Never commit `.env*` (except `.env.example`).

## Output

Tight. One line per non-empty category. Two groups: `Done:` (actions taken) and `Needs your call:` (only when something was branched off or skipped). End with `Safe to kill.` or, if you isolated something onto a branch, `Safe to kill — review <branch> when you're back.`
