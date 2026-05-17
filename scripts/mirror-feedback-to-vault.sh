#!/bin/bash
set -euo pipefail

# Mirror a single agent feedback rating (as JSON via stdin) to vault as markdown.
# Usage: echo '{"project": "...", ...}' | scripts/mirror-feedback-to-vault.sh
# Input: JSON via stdin with fields {project, timestamp, agent, rating, notes, task?}
# Output: markdown file in ../vault/feedback/<agent>/<project>-<safe-ts>.md
# Idempotent: skips if target .md already exists.

# Check jq is available
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq not found on PATH. Install jq to continue." >&2
  exit 1
fi

# Read JSON from stdin
json_input=$(cat)

# Check if no input was provided
if [[ -z "$json_input" ]]; then
  echo "Usage: echo '{...rating JSON...}' | scripts/mirror-feedback-to-vault.sh"
  echo "Input: JSON with fields {project, timestamp, agent, rating, notes, task?}"
  echo "Output: markdown in ../vault/feedback/<agent>/<project>-<safe-ts>.md"
  echo "Idempotent: skips if target .md already exists."
  exit 1
fi

# Parse JSON. Extract required fields: project, timestamp, agent, rating, notes
# Optional: task
project=$(jq -r '.project' <<< "$json_input" 2>/dev/null) || {
  echo "ERROR: Failed to parse JSON or missing 'project' field" >&2
  exit 1
}
timestamp=$(jq -r '.timestamp' <<< "$json_input" 2>/dev/null) || {
  echo "ERROR: Missing 'timestamp' field" >&2
  exit 1
}
agent=$(jq -r '.agent' <<< "$json_input" 2>/dev/null) || {
  echo "ERROR: Missing 'agent' field" >&2
  exit 1
}
rating=$(jq -r '.rating' <<< "$json_input" 2>/dev/null) || {
  echo "ERROR: Missing 'rating' field" >&2
  exit 1
}
notes=$(jq -r '.notes' <<< "$json_input" 2>/dev/null) || {
  echo "ERROR: Missing 'notes' field" >&2
  exit 1
}
task=$(jq -r '.task // empty' <<< "$json_input" 2>/dev/null) || true

# Validate rating is canonical
case "$rating" in
  poor|adequate|effective)
    ;;
  *)
    echo "ERROR: Invalid rating '$rating' — must be poor, adequate, or effective" >&2
    exit 1
    ;;
esac

# Compute safe-timestamp: replace colons with hyphens
# E.g., 2026-05-12T11:15:30Z → 2026-05-12T11-15-30Z
safe_ts="${timestamp//:/-}"

# Output path: ../vault/feedback/<agent>/<project>-<safe-ts>.md
vault_dir="../vault/feedback/$agent"
vault_path="$vault_dir/$project-$safe_ts.md"

# If target already exists, skip (idempotent)
if [[ -f "$vault_path" ]]; then
  exit 0
fi

# Create agent subdir
mkdir -p "$vault_dir"

# Build frontmatter
{
  echo "---"
  echo "agent: $agent"
  echo "project: $project"
  echo "rating: $rating"
  echo "timestamp: $timestamp"
  if [[ -n "$task" ]]; then
    echo "task: $task"
  fi
  echo "---"
  echo ""
  echo "$notes"
} > "$vault_path"

# Print output path on success
echo "$vault_path"
