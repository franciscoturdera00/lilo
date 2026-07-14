#!/usr/bin/env bash
# Deterministic half of the outbox sweep.
#
# Finds every unprocessed outbox message, archives it, and records exactly what
# it moved. The sweeper subagent does NOT decide what the work-list is and does
# NOT get to author the counts — this script does both, so a model that drops
# messages from its summary can be caught by comparing its output against
# swept-manifest.txt.
#
# Context: a sweep on 2026-07-14 archived 42 messages and reported 3. Nothing
# errored and the outbox was empty afterward, so every "did it work" check
# passed. The manifest exists so that can never be invisible again.
#
# Usage: ./scripts/sweep-outbox.sh   (run from the lilo repo root)
# Output: writes $MANIFEST, prints the archived paths, exits non-zero on trouble.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

MANIFEST="${MANIFEST:-/tmp/lilo-sweep-manifest.txt}"
: > "$MANIFEST"

status=0
found=0
swept=0

# Pin the work-list up front. Sorted so runs are reproducible.
pending="$(find .. -mindepth 3 -maxdepth 3 -path "*/.lilo-outbox/*.json" \
    -not -path "*/processed/*" -not -path "$REPO_ROOT/*" 2>/dev/null | sort)"

if [ -z "$pending" ]; then
    echo "FOUND=0" >&2
    echo "SWEPT=0" >&2
    exit 0
fi

while IFS= read -r src; do
    [ -n "$src" ] || continue
    found=$((found + 1))

    outbox_dir="$(dirname "$src")"
    dest_dir="$outbox_dir/processed"

    if ! mkdir -p "$dest_dir" 2>/dev/null; then
        echo "ERROR: cannot create $dest_dir" >&2
        status=1
        continue
    fi

    dest="$dest_dir/$(basename "$src")"

    # Never clobber an existing archive entry — a name collision means two
    # distinct messages, and silently overwriting one destroys it.
    if [ -e "$dest" ]; then
        dest="$dest_dir/$(basename "$src" .json).dup-$$.json"
        echo "WARN: archive name collision, saved as $dest" >&2
    fi

    if ! mv "$src" "$dest" 2>/dev/null; then
        echo "ERROR: mv failed for $src" >&2
        status=1
        continue
    fi

    # The manifest is the ground truth the subagent is measured against.
    printf '%s\n' "$dest" >> "$MANIFEST"
    swept=$((swept + 1))
done <<< "$pending"

echo "FOUND=$found" >&2
echo "SWEPT=$swept" >&2
echo "MANIFEST=$MANIFEST" >&2

if [ "$found" -ne "$swept" ]; then
    echo "ERROR: incomplete sweep — found $found, archived $swept" >&2
    status=1
fi

cat "$MANIFEST"
exit "$status"
