#!/bin/bash
set -euo pipefail

# Render vault project notes from pipeline.json
# Consumes the output of render-pipeline.sh and emits per-project markdown notes
# at ../vault/projects/<name>.md
# Idempotent: overwrites cleanly.
#
# Usage: render-pipeline-vault.sh
# Requires: pipeline.json in the current working directory
# Output: markdown files at ../vault/projects/*.md
# On error: prints to stderr and exits non-zero

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LILO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VAULT_ROOT="$(cd "$LILO_ROOT/.." && pwd)/vault"
PIPELINE_JSON="$LILO_ROOT/pipeline.json"

# Check jq is available
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq not found on PATH. Install jq to continue." >&2
  exit 1
fi

# Check pipeline.json exists
if [[ ! -f "$PIPELINE_JSON" ]]; then
  echo "ERROR: pipeline.json not found at $PIPELINE_JSON" >&2
  echo "ERROR: Run render-pipeline.sh first." >&2
  exit 1
fi

# Validate JSON
if ! jq empty "$PIPELINE_JSON" 2>/dev/null; then
  echo "ERROR: pipeline.json is not valid JSON" >&2
  exit 1
fi

# Create projects dir
mkdir -p "$VAULT_ROOT/projects"

# Function to normalize status
normalize_status() {
  local status="$1"
  case "$status" in
    complete|completed|closed|finished)
      echo "done"
      ;;
    in_progress)
      echo "active"
      ;;
    unknown|""|null)
      echo "solo"
      ;;
    *)
      echo "active"
      ;;
  esac
}

# Process each project in pipeline.json
project_count=$(jq '.projects | length' "$PIPELINE_JSON")

if [[ "$project_count" -eq 0 ]]; then
  echo "wrote 0 project notes"
  exit 0
fi

written_count=0

# Create a shell function to process one project
render_project_note() {
  local project_json="$1"

  name=$(jq -r '.name' <<< "$project_json")
  local_path=$(jq -r '.local_path' <<< "$project_json")
  status=$(jq -r '.status // "unknown"' <<< "$project_json")
  phase=$(jq -r '.phase // ""' <<< "$project_json")
  updated_at=$(jq -r '.updated_at // null' <<< "$project_json")
  summary=$(jq -r '.summary // ""' <<< "$project_json")
  context=$(jq -r '.context // ""' <<< "$project_json")
  team_size=$(jq -r '.team_size // 0' <<< "$project_json")
  open_tasks_count=$(jq -r '.open_tasks_count // 0' <<< "$project_json")
  outbox_pending=$(jq -r '.outbox_pending // 0' <<< "$project_json")
  outbox_archived=$(jq -r '.outbox_archived // 0' <<< "$project_json")
  pm_live=$(jq -r '.pm_live // false' <<< "$project_json")

  # Normalize status
  normalized_status=$(normalize_status "$status")

  # Vault file path
  vault_file="$VAULT_ROOT/projects/$name.md"

  # Build markdown file
  {
    # Frontmatter
    echo "---"
    echo "project: $name"
    echo "status: $normalized_status"
    echo "phase: $phase"
    echo "updated_at: $updated_at"
    echo "team_size: $team_size"
    echo "open_tasks_count: $open_tasks_count"
    echo "outbox_pending: $outbox_pending"
    echo "outbox_archived: $outbox_archived"
    echo "pm_live: $pm_live"
    echo "local_path: $local_path"
    echo "---"
    echo ""

    # Project title
    echo "# $name"
    echo ""

    # Summary block
    if [[ -n "$summary" ]]; then
      echo "> **Summary:** $summary"
      echo ""
    fi

    # Context section
    echo "## Context"
    echo ""
    if [[ -n "$context" ]]; then
      echo "$context"
    else
      echo "_No context recorded yet._"
    fi
    echo ""

    # Open tasks section
    echo "## Open tasks"
    echo ""
    tasks_count=$(jq '.active_tasks | length' <<< "$project_json")
    if [[ "$tasks_count" -gt 0 ]]; then
      jq -r '.active_tasks[] | "- **\(.id // .name // "unnamed")**\(if .status then " (\(.status))" else "" end)\(if .description or .note then " — " + (.description // .note // "") else "" end)"' <<< "$project_json"
    else
      echo "_None_"
    fi
    echo ""

    # Open decisions section
    echo "## Open decisions"
    echo ""
    decisions_count=$(jq '.open_decisions | length' <<< "$project_json")
    if [[ "$decisions_count" -gt 0 ]]; then
      jq -r '.open_decisions[] | if type == "object" then "- **\(.id // "")**\(if .decision then ": " + .decision else "" end)" else "- " + . end' <<< "$project_json"
    else
      echo "_None_"
    fi
    echo ""

    # Team section
    echo "## Team"
    echo ""
    team_count=$(jq '.team | length' <<< "$project_json")
    if [[ "$team_count" -gt 0 ]]; then
      jq -r '.team[] | if .role then "- **\(.role // .name // "")**\(if .model then " (\(.model))" else "" end)" else "- **\(.name // "")**\(if .model then " (\(.model))" else "" end)" end' <<< "$project_json"
    else
      echo "_No team recruited yet._"
    fi
    echo ""

    # Links section
    echo "## Links"
    echo ""
    echo "- [Outbox archive](../outbox/$name/)"
    echo "- [Decisions](../decisions/$name/)"
    echo "- Local repo: \`$local_path\`"

  } > "$vault_file"
}

# Main loop: iterate projects and render each
while IFS= read -r project_json; do
  render_project_note "$project_json"
  ((written_count++))
done < <(jq -c '.projects[]' "$PIPELINE_JSON")

echo "wrote $written_count project notes"
