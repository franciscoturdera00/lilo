---
name: check-inbox
description: Read new messages from Lilo in .lilo-inbox/, summarize them into the working plan, and archive. Use at session start, when Lilo nudges you (tmux prompt or Desktop message), or whenever you suspect new instructions have arrived. Plumbing only — does not act on the messages, that's the PM's judgment call.
user-invocable: true
allowed-tools:
  - Read
  - Bash(ls *)
  - Bash(mkdir *)
  - Bash(mv *)
  - Bash(find *)
---

# /check-inbox — Read new Lilo messages

Scan `.lilo-inbox/` for unread messages from Lilo, read them in order, then archive so they are not re-processed.

## What this skill does (and does not)

**Does:** discover new files, read them, summarize each one inline so the operator (or the reviewing human) sees what arrived, archive to `.lilo-inbox/processed/`.

**Does not:** act on the instructions. After summarizing, decide what to do with the contents using your own judgment as the PM/operator. If a message requests work, incorporate it into your plan; if it's a nudge, acknowledge and continue; if it's ambiguous, write a `question` outbox message back to Lilo.

## Steps

1. List `.lilo-inbox/*.md` (and `*.json` if any), **excluding** `.lilo-inbox/processed/`.
   ```bash
   find .lilo-inbox -maxdepth 1 -type f \( -name '*.md' -o -name '*.json' \) | sort
   ```
2. If the list is empty, say `Inbox empty.` and stop.
3. For each file in timestamp order:
   - Read the full file
   - Print a one-line summary: `<filename>: <first meaningful line or title>`. If the file starts with `in_reply_to: <id>`, include it (`(answers <id>)`) — it is the outbox question or blocker this message closes
   - If the message is long, also print a 2-3 bullet summary of the ask
4. After reading every file, create `.lilo-inbox/processed/` if needed and move all read files into it:
   ```bash
   mkdir -p .lilo-inbox/processed
   mv .lilo-inbox/<file1> .lilo-inbox/<file2> ... .lilo-inbox/processed/
   ```
5. State `Inbox cleared. N message(s) processed.` and then — **outside the skill** — decide how to act on the content.

## When to run

- **On session start** (first thing after reading `.team-state.json` if in team mode).
- **When Lilo nudges you**, via `tmux send-keys` or a Desktop message from Lilo — any message saying "check your inbox" or similar. The nudge carries no instructions; the inbox file does.
- **After long operations** that may have spanned several minutes — Lilo may have queued something while you were busy.
- **Never on a loop.** The inbox is async but not high-frequency. Polling it wastes tokens. Rely on explicit nudges and session-start checks.

## Notes

- The `processed/` archive is permanent — do not delete it. It's the audit trail of everything Lilo has asked you to do.
- If you find a message you already handled (duplicate from a re-nudge), still archive it; better to be idempotent than to leave stale files in the inbox.
- Messages are authored by Lilo on behalf of the operator. Treat them as you would direct instructions from the user.
