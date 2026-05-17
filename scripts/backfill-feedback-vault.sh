#!/bin/bash
set -euo pipefail

# One-shot backfill: read ./agent-feedback.jsonl line-by-line and pipe each
# rating into the mirror script. Idempotent.
#
# Usage: backfill-feedback-vault.sh [from cwd = lilo repo root]

total_lines=0
total_mirrored=0
total_skipped=0
total_errored=0

# Read agent-feedback.jsonl line-by-line
while IFS= read -r line; do
  # Skip empty lines
  if [[ -z "$line" ]]; then
    continue
  fi

  ((total_lines++))

  # Validate JSON (try to parse it, skip if invalid)
  if ! jq -e . <<< "$line" &>/dev/null; then
    ((total_errored++))
    continue
  fi

  # Pipe the JSON line into the mirror script, capture stdout
  if output=$(echo "$line" | ./scripts/mirror-feedback-to-vault.sh 2>/dev/null); then
    # If stdout is non-empty (a path), the file was newly mirrored
    if [[ -n "$output" ]]; then
      ((total_mirrored++))
    else
      # Empty stdout means it already existed (skipped)
      ((total_skipped++))
    fi
  else
    # Mirror script failed (non-zero exit)
    ((total_errored++))
  fi
done < ./agent-feedback.jsonl

# Print summary
echo "Backfill summary: lines=$total_lines, mirrored=$total_mirrored, skipped=$total_skipped, errored=$total_errored"
