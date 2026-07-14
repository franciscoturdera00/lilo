#!/usr/bin/env python3
"""Rebuild agent-feedback.jsonl entries for a given day from the archived outbox messages.

The 2026-07-14 sweep wrote 34 feedback entries when the archived messages actually
contained 85 ratings, and blanked the `notes` on 22 of the 34 it did write. The
registry-refinement loop reads this log, so the log has to match the source.

The archived JSON in <project>/.lilo-outbox/processed/ is the source of truth. This
drops every entry stamped with --day and regenerates them from those files.

Usage:
  ./scripts/rebuild-feedback-from-archive.py --day 2026-07-14 [--apply]

Without --apply it prints what it would change and writes nothing.
"""
import argparse
import glob
import json
import os
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(REPO_ROOT, "agent-feedback.jsonl")


def canonical(rating):
    """Normalize a PM-written rating to poor|adequate|effective, or None to drop."""
    if rating is None:
        return None
    r = str(rating).strip().lower()
    if r in ("poor", "adequate", "effective"):
        return r
    if r in ("good", "excellent", "great"):
        return "effective"
    if r in ("not-used", "not_used", "unused", "n/a"):
        return None
    try:
        n = float(r)
    except ValueError:
        return None
    if n >= 5:
        return "effective"
    if n >= 3:
        return "adequate"
    return "poor"


def archived_on(day):
    """Archived message files whose inode-change time falls on `day` (mv stamps ctime)."""
    hits = []
    for outbox in glob.glob(os.path.join(REPO_ROOT, "..", "*", ".lilo-outbox", "processed")):
        files = glob.glob(os.path.join(outbox, "*.json"))
        if not files:
            continue
        out = subprocess.run(
            ["stat", "-f", "%Sc|%N", "-t", "%Y-%m-%d"] + files,
            capture_output=True, text=True,
        ).stdout
        for line in out.strip().splitlines():
            ctime, _, path = line.partition("|")
            if ctime == day:
                hits.append(path)
    return sorted(hits)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--day", required=True, help="YYYY-MM-DD")
    ap.add_argument("--apply", action="store_true", help="write the repaired log")
    args = ap.parse_args()

    kept, dropped = [], 0
    with open(LOG) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            d = json.loads(line)
            if d.get("timestamp", "").startswith(args.day):
                dropped += 1
            else:
                kept.append(d)

    rebuilt, skipped, no_note = [], 0, 0
    for path in archived_on(args.day):
        try:
            msg = json.load(open(path))
        except Exception as exc:
            print(f"  WARN unparseable, no ratings recovered: {path} ({exc})", file=sys.stderr)
            continue
        reports = msg.get("agent_report") or []
        if not isinstance(reports, list):
            continue
        # The archived file's own mtime is when the PM wrote it — a truer timestamp
        # than "when the sweep happened", and it keeps the log chronologically honest.
        ts = subprocess.run(
            ["stat", "-f", "%Sm", "-t", "%Y-%m-%dT%H:%M:%SZ", path],
            capture_output=True, text=True,
        ).stdout.strip()
        for r in reports:
            if not isinstance(r, dict):
                continue
            rating = canonical(r.get("rating"))
            if rating is None:
                skipped += 1
                continue
            # PMs write the field as `note` (singular); the log schema uses `notes`.
            # That mismatch is how 22 entries ended up blank.
            note = (r.get("note") or r.get("notes") or "").strip()
            if not note:
                no_note += 1
            rebuilt.append({
                "project": msg.get("project", "unknown"),
                "timestamp": ts,
                "agent": r.get("agent", "unknown"),
                "rating": rating,
                "notes": note,
            })

    print(f"kept (other days):   {len(kept)}")
    print(f"dropped ({args.day}): {dropped}")
    print(f"rebuilt from archive: {len(rebuilt)}  (blank-note: {no_note}, unrecognized-rating dropped: {skipped})")
    print(f"new total:            {len(kept) + len(rebuilt)}")

    # Idempotency guard. Entries are dropped by --day (the timestamp the BROKEN sweep
    # stamped) but rebuilt with the archived file's mtime (the PM's real write time).
    # Those two partitions coincide exactly once: on the first repair. Afterwards the
    # rebuilt entries carry May/June timestamps, so a second --day 2026-07-14 run would
    # drop only a few and re-add all 79 -- duplicating ~70. Dedupe the union on a
    # content key so re-running is a no-op instead of a re-corruption.
    def key(d):
        return (d.get("project"), d.get("agent"), d.get("timestamp"),
                d.get("rating"), d.get("notes"))

    seen, out, dupes = set(), [], 0
    for d in kept + rebuilt:
        k = key(d)
        if k in seen:
            dupes += 1
            continue
        seen.add(k)
        out.append(d)

    if dupes:
        print(f"deduped:              {dupes} (already-repaired entries — re-run is a no-op)")
    print(f"final total:          {len(out)}")

    if not args.apply:
        print("\ndry run — pass --apply to write")
        return

    out.sort(key=lambda d: d.get("timestamp", ""))
    with open(LOG, "w") as fh:
        for d in out:
            fh.write(json.dumps(d) + "\n")
    print(f"\nwrote {len(out)} entries to {LOG}")


if __name__ == "__main__":
    main()
