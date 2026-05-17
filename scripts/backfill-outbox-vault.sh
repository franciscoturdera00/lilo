#!/bin/bash
set -euo pipefail

# One-shot backfill: walk every archived JSON in ../<project>/.lilo-outbox/processed/
# and mirror it to the vault. Idempotent.
#
# Usage: backfill-outbox-vault.sh [from cwd = lilo repo root]

total_found=0
total_mirrored=0
total_skipped=0
total_errored=0

# Find all archived JSONs across all sibling projects
# Same find shape as outbox-sweeper, but restricted to processed/ subdir
while IFS= read -r json_path; do
  ((total_found++))

  # Call mirror script on this file, capture stdout only (not stderr)
  if output=$(./scripts/mirror-outbox-to-vault.sh "$json_path" 2>/dev/null); then
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
done < <(find .. -mindepth 4 -maxdepth 4 -path "*/.lilo-outbox/processed/*.json" -not -path "$PWD/*" 2>/dev/null)

# Print summary
echo "Backfill summary: found=$total_found, mirrored=$total_mirrored, skipped=$total_skipped, errored=$total_errored"
