#!/bin/bash
set -euo pipefail

# Mirror a single decision event (JSON via stdin) to vault as ADR markdown.
# Usage: echo '{"ts": "...", "kind": "decision", "data": {...}}' | mirror-decision-to-vault.sh "<project-name>"
# Input: JSON via stdin with event schema {ts, kind: "decision", data: {summary, phase, rationale?, alternatives_considered?}}
# Project name: positional argument $1
# Output: markdown file in ../vault/decisions/<project>/<safe-ts>-<slug>.md
# Idempotent: skips if target .md already exists.

# Check jq is available
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq not found on PATH. Install jq to continue." >&2
  exit 1
fi

# Check project arg
if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]]; then
  echo "Usage: echo '{...decision event JSON...}' | mirror-decision-to-vault.sh \"<project-name>\""
  echo "Input: JSON with fields {ts, kind: \"decision\", data: {summary, phase, rationale?, alternatives_considered?}}"
  echo "Output: markdown in ../vault/decisions/<project>/<safe-ts>-<slug>.md"
  echo "Idempotent: skips if target .md already exists."
  exit 1
fi

project="$1"

# Read JSON from stdin
json_input=$(cat)

# Check if no input was provided
if [[ -z "$json_input" ]]; then
  echo "ERROR: No JSON input provided via stdin" >&2
  exit 1
fi

# Parse JSON
kind=$(jq -r '.kind' <<< "$json_input" 2>/dev/null) || {
  echo "ERROR: Failed to parse JSON or missing 'kind' field" >&2
  exit 1
}
ts=$(jq -r '.ts' <<< "$json_input" 2>/dev/null) || {
  echo "ERROR: Missing 'ts' field" >&2
  exit 1
}
summary=$(jq -r '.data.summary' <<< "$json_input" 2>/dev/null) || {
  echo "ERROR: Missing 'data.summary' field" >&2
  exit 1
}
phase=$(jq -r '.data.phase' <<< "$json_input" 2>/dev/null) || {
  echo "ERROR: Missing 'data.phase' field" >&2
  exit 1
}
rationale=$(jq -r '.data.rationale // empty' <<< "$json_input" 2>/dev/null) || true
alternatives_considered=$(jq -r '.data.alternatives_considered // empty' <<< "$json_input" 2>/dev/null) || true

# Validate kind
if [[ "$kind" != "decision" ]]; then
  echo "ERROR: Invalid event kind '$kind' — expected 'decision'" >&2
  exit 1
fi

# Validate summary is not empty
if [[ -z "$summary" ]]; then
  echo "ERROR: data.summary is empty or missing — cannot create ADR without a summary" >&2
  exit 1
fi

# Compute safe-timestamp: replace colons with hyphens
# E.g., 2026-05-12T11:15:30Z → 2026-05-12T11-15-30Z
safe_ts="${ts//:/-}"

# Compute slug from summary:
# - lowercase
# - replace non-alphanumeric (except hyphens) with hyphens
# - collapse consecutive hyphens
# - trim leading/trailing hyphens
# - truncate to 60 chars
slug=$(echo "$summary" | \
  tr '[:upper:]' '[:lower:]' | \
  sed 's/[^a-z0-9-]/-/g' | \
  sed 's/-\+/-/g' | \
  sed 's/^-\|-$//g' | \
  cut -c1-60)

# Validate slug is not empty after sanitization
if [[ -z "$slug" ]]; then
  echo "ERROR: Summary sanitization resulted in empty slug: '$summary'" >&2
  exit 1
fi

# Output path: ../vault/decisions/<project>/<safe-ts>-<slug>.md
vault_dir="../vault/decisions/$project"
vault_path="$vault_dir/$safe_ts-$slug.md"

# If target already exists, skip (idempotent)
if [[ -f "$vault_path" ]]; then
  exit 0
fi

# Create project subdir
mkdir -p "$vault_dir"

# Build and write markdown
{
  echo "---"
  echo "project: $project"
  echo "phase: $phase"
  echo "date: $ts"
  echo "status: active"
  echo "---"
  echo ""
  echo "# $summary"

  # Add rationale if present
  if [[ -n "$rationale" ]]; then
    echo ""
    echo "$rationale"
  fi

  # Add alternatives if present
  if [[ -n "$alternatives_considered" ]]; then
    echo ""
    echo "## Alternatives considered"
    echo ""
    # alternatives_considered is a JSON array; iterate and format
    jq -r '.[] | "- \(.)"' <<< "$alternatives_considered" 2>/dev/null || true
  fi
} > "$vault_path"

# Print output path on success
echo "$vault_path"
