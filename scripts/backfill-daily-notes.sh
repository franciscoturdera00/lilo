#!/bin/bash
set -euo pipefail

# One-shot backfill: walk every archived JSON in ../<project>/.lilo-outbox/processed/
# and append entries to daily notes. Idempotent (append script skips dupes).
#
# Usage: backfill-daily-notes.sh [from cwd = lilo repo root]

total_walked=0
total_appended=0
total_skipped=0
total_errored=0

# Find all archived JSONs across all sibling projects
# Same find shape as outbox-sweeper, but restricted to processed/ subdir
while IFS= read -r json_path; do
  ((total_walked++))

  # Extract project and summary from JSON
  if ! project=$(jq -r '.project // empty' "$json_path" 2>/dev/null); then
    ((total_errored++))
    continue
  fi
  if ! summary=$(jq -r '.summary // empty' "$json_path" 2>/dev/null); then
    ((total_errored++))
    continue
  fi

  # Extract timestamp from filename
  # Try patterns as in mirror-outbox-to-vault.sh
  filename=$(basename "$json_path")
  iso_timestamp=""

  # Try strict ISO-safe first (YYYY-MM-DDTHH-MM-SSZ)
  if [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})-([0-9]{2})-([0-9]{2})Z ]]; then
    iso_timestamp="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}Z"
  # Try YYYY-MM-DDTHHMMSS
  elif [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
    iso_timestamp="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}Z"
  # Try YYYY-MM-DDTHHMM
  elif [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})([0-9]{2}) ]]; then
    iso_timestamp="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:00Z"
  # Try YYYY-MM-DDTHH-MM
  elif [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})-([0-9]{2}) ]]; then
    iso_timestamp="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:00Z"
  # Fallback: just extract date, no time
  elif [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
    iso_timestamp="${BASH_REMATCH[1]}T00:00:00Z"
  else
    # Last resort: use current time
    iso_timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  fi

  # Call append script on this file
  # The append script prints the entry on success, nothing on skip.
  # Capture both stdout and stderr to detect idempotency.
  if output=$(./scripts/append-to-daily-note.sh "$project" "$summary" -t "$iso_timestamp" 2>/dev/null); then
    # If stdout is non-empty (the entry line), it was newly appended
    if [[ -n "$output" ]]; then
      ((total_appended++))
    else
      # Empty stdout means it already existed (skipped)
      ((total_skipped++))
    fi
  else
    # Append script failed (non-zero exit)
    ((total_errored++))
  fi
done < <(find .. -mindepth 4 -maxdepth 4 -path "*/.lilo-outbox/processed/*.json" -not -path "$PWD/*" 2>/dev/null)

# Print summary
echo "walked=$total_walked, appended=$total_appended, skipped=$total_skipped, errored=$total_errored"
