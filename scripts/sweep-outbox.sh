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
# Usage: MANIFEST=<run-dir>/manifest.txt ./scripts/sweep-outbox.sh
#   (run from the lilo repo root). Without MANIFEST, a fresh per-run dir is
#   created with mktemp. Never share a manifest path between runs: two sweeps
#   writing one file clobber each other's work-list.
#   PROJECT=<name> limits the sweep to ../<name>/.lilo-outbox (event-driven
#   sweeps after a PM pings Lilo). Unset sweeps every sibling.
# Output: writes $MANIFEST, prints MANIFEST=<path> to stderr (always, even on
# an empty sweep) and the archived paths to stdout, exits non-zero on trouble.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Validate PROJECT before creating or announcing a manifest: a bad name must
# fail loudly, never leave an empty manifest that reads like a clean sweep.
if [ -n "${PROJECT:-}" ]; then
    case "$PROJECT" in
        */*|.|..|"$(basename "$REPO_ROOT")")
            echo "ERROR: PROJECT must be a bare sibling project name, got '$PROJECT'" >&2; exit 1 ;;
    esac
    if [ ! -d "../$PROJECT" ]; then
        echo "ERROR: no sibling project '../$PROJECT'" >&2
        exit 1
    fi
fi

if [ -z "${MANIFEST:-}" ]; then
    RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lilo-sweep.XXXXXX")" || { echo "ERROR: mktemp failed" >&2; exit 1; }
    MANIFEST="$RUN_DIR/manifest.txt"
fi
: > "$MANIFEST" || { echo "ERROR: cannot write $MANIFEST" >&2; exit 1; }
echo "MANIFEST=$MANIFEST" >&2

status=0
found=0
swept=0

# Pin the work-list up front. Sorted so runs are reproducible.
if [ -n "${PROJECT:-}" ]; then
    pending="$(find "../$PROJECT/.lilo-outbox" -mindepth 1 -maxdepth 1 -name '*.json' -type f 2>/dev/null | sort)"
else
    pending="$(find .. -mindepth 3 -maxdepth 3 -path "*/.lilo-outbox/*.json" \
        -not -path "*/processed/*" -not -path "$REPO_ROOT/*" 2>/dev/null | sort)"
fi

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

if [ "$found" -ne "$swept" ]; then
    echo "ERROR: incomplete sweep — found $found, archived $swept" >&2
    status=1
fi

cat "$MANIFEST"
exit "$status"
