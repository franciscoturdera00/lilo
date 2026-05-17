#!/bin/bash
set -euo pipefail

# One-shot backfill: find all .team-history.jsonl in sibling projects, grep for decision
# events, and pipe each into the mirror script. Idempotent.
#
# Usage: backfill-decisions-vault.sh [from cwd = lilo repo root]

total_found=0
total_written=0
total_skipped=0
total_errored=0

# Find all .team-history.jsonl files in sibling projects
# Pattern: ../<project>/.team-history.jsonl but exclude this repo ($PWD)
while IFS= read -r history_file; do
  # Extract project name from path: ../<project>/.team-history.jsonl
  project=$(basename "$(dirname "$history_file")")

  # Read history file line-by-line
  while IFS= read -r line; do
    # Skip empty lines
    if [[ -z "$line" ]]; then
      continue
    fi

    # Validate JSON and check if kind == "decision"
    if ! jq -e '.kind == "decision"' <<< "$line" &>/dev/null; then
      continue
    fi

    ((total_found++))

    # Pipe the JSON line into the mirror script, capture stdout and exit code
    if output=$(echo "$line" | ./scripts/mirror-decision-to-vault.sh "$project" 2>/dev/null); then
      # If stdout is non-empty (a path), the file was newly mirrored
      if [[ -n "$output" ]]; then
        ((total_written++))
      else
        # Empty stdout means it already existed (skipped)
        ((total_skipped++))
      fi
    else
      # Mirror script failed (non-zero exit)
      ((total_errored++))
    fi
  done < "$history_file"
done < <(find .. -mindepth 2 -maxdepth 2 -name '.team-history.jsonl' -not -path "$PWD/*")

# Print summary
echo "Backfill summary: found=$total_found, written=$total_written, skipped=$total_skipped, errored=$total_errored"
