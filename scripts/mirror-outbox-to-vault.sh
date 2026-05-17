#!/bin/bash
set -euo pipefail

# Mirror a single archived JSON message to vault as markdown.
# Usage: mirror-outbox-to-vault.sh <path-to-json>
# Input: absolute path to a *.json in either .lilo-outbox/ or .lilo-outbox/processed/
# Output: markdown file in ../vault/outbox/<project>/<filename>.md
# Idempotent: skips if target .md already exists.

if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]]; then
  echo "Usage: mirror-outbox-to-vault.sh <path-to-json>"
  echo "Input: absolute path to a JSON message in .lilo-outbox/ or .lilo-outbox/processed/"
  echo "Output: markdown in ../vault/outbox/<project>/<filename-without-.json>.md"
  echo "Idempotent: skips if target .md already exists."
  exit 0
fi

json_path="$1"

# Check jq is available
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq not found on PATH. Install jq to continue." >&2
  exit 1
fi

# Check file exists
if [[ ! -f "$json_path" ]]; then
  echo "ERROR: File not found: $json_path" >&2
  exit 1
fi

# Parse JSON. Extract type, priority, project, summary, detail, agent_report (optional).
type=$(jq -r '.type' "$json_path" 2>/dev/null) || {
  echo "ERROR: Failed to parse JSON: $json_path" >&2
  exit 1
}
priority=$(jq -r '.priority' "$json_path")
json_project=$(jq -r '.project' "$json_path")
summary=$(jq -r '.summary' "$json_path")
detail=$(jq -r '.detail' "$json_path")
agent_report=$(jq -r '.agent_report // empty' "$json_path")

# Derive project from path. Path shape: /path/to/<project>/.lilo-outbox[/processed]/*.json
# Parent-of-parent-of-parent is the project dir.
path_project=$(echo "$json_path" | sed 's|/[^/]*/.lilo-outbox/processed/[^/]*$||; s|/[^/]*/.lilo-outbox/[^/]*$||' | xargs basename)

# Cross-check project. Prefer JSON field if they disagree.
if [[ "$path_project" != "$json_project" ]]; then
  echo "WARNING: Project mismatch in $json_path — path says '$path_project', JSON says '$json_project'. Using JSON field." >&2
fi
project="$json_project"

# Extract timestamp from filename.
# Try patterns:
# 1. YYYY-MM-DDTHH-MM-SSZ (converted ISO safe, convert back to ISO)
# 2. YYYY-MM-DDTHHMMSS-* (compact, prefix with T)
# 3. YYYY-MM-DDTHHMM-* (hour-minute compact)
# 4. YYYY-MM-DDTHH-MM-* (hour-minute with hyphens)
# Fallback: just extract the date part if time is unparseable
filename=$(basename "$json_path")

# Try strict ISO-safe first (YYYY-MM-DDTHH-MM-SSZ)
if [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})-([0-9]{2})-([0-9]{2})Z ]]; then
  # Convert back to ISO: YYYY-MM-DDTHH:MM:SSZ
  timestamp="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}Z"
# Try YYYY-MM-DDTHHMMSS
elif [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
  timestamp="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:${BASH_REMATCH[4]}Z"
# Try YYYY-MM-DDTHHMM
elif [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})([0-9]{2}) ]]; then
  timestamp="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:00Z"
# Try YYYY-MM-DDTHH-MM
elif [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})-([0-9]{2}) ]]; then
  timestamp="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}:${BASH_REMATCH[3]}:00Z"
# Fallback: just extract date, no time
elif [[ "$filename" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
  timestamp="${BASH_REMATCH[1]}T00:00:00Z"
else
  # Last resort: use filename as-is
  timestamp="$filename"
fi

# Output markdown filename (without .json, safe-form with hyphens for colons)
md_filename="${filename%.json}.md"

# Vault path: ../vault/outbox/<project>/<md_filename>
# Relative to lilo repo root
vault_dir="../vault/outbox/$project"
vault_path="$vault_dir/$md_filename"

# If target already exists, skip (idempotent)
if [[ -f "$vault_path" ]]; then
  exit 0
fi

# Create project subdir
mkdir -p "$vault_dir"

# Build frontmatter. Escape quotes in summary.
summary_escaped=$(echo "$summary" | sed 's/"/\\"/g')

# Write markdown
{
  echo "---"
  echo "project: $project"
  echo "type: $type"
  echo "priority: $priority"
  echo "timestamp: $timestamp"
  echo "summary: \"$summary_escaped\""

  # Calculate relative path from vault_path to json_path
  # Both are absolute, compute relative
  relative_json=$(python3 -c "import os; print(os.path.relpath('$json_path', '$vault_dir'))" 2>/dev/null || echo "$json_path")
  echo "source_json: $relative_json"

  echo "---"
  echo ""
  echo "$detail"

  # Append agent_report if present and non-empty
  if [[ -n "$agent_report" ]]; then
    # agent_report is a JSON array. Parse each entry: {agent, rating, notes}
    echo ""
    echo "## Agent report"
    echo ""
    # Use jq to iterate and format. Key is .agent, not .role
    jq -r '.[] | "- **\(.agent)** (\(.rating)): \(.notes)"' <<< "$agent_report" 2>/dev/null || true
  fi
} > "$vault_path"

# Print output path
echo "$vault_path"
