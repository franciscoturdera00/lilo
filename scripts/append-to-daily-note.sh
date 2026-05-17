#!/bin/bash
set -euo pipefail

# Append a one-line entry to a daily note in the vault.
# Idempotent: skips if the exact entry line already exists.
# Sorts the activity-log section chronologically by HH:MM after each append.
#
# Usage: append-to-daily-note.sh <project> <summary> [-t <iso-timestamp>]
#
# Examples:
#   append-to-daily-note.sh amazon-buy-scraper "shipped — pushed to public repo"
#   append-to-daily-note.sh starwood "blocker: figma asset URL expired" -t 2026-05-12T18:30:00Z

if [[ $# -lt 2 ]] || [[ "$1" == "--help" ]]; then
  echo "Usage: append-to-daily-note.sh <project> <summary> [-t <iso-timestamp>]" >&2
  echo "" >&2
  echo "Appends a one-line entry to ../vault/daily/<YYYY-MM-DD>.md" >&2
  echo "Times use local time. If no -t, uses current time." >&2
  exit 1
fi

project="$1"
summary="$2"
iso_timestamp=""

# Parse optional -t flag
while [[ $# -gt 2 ]]; do
  case "$3" in
    -t)
      if [[ $# -lt 4 ]]; then
        echo "ERROR: -t requires an argument" >&2
        exit 1
      fi
      iso_timestamp="$4"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown option: $3" >&2
      exit 1
      ;;
  esac
done

# Derive local date and time
if [[ -z "$iso_timestamp" ]]; then
  # Use current time
  local_date=$(date +'%Y-%m-%d')
  local_time=$(date +'%H:%M')
else
  # Convert ISO timestamp (assumed UTC) to local date and time
  # macOS: date -j -f '%Y-%m-%dT%H:%M:%SZ' "<iso>" +'%Y-%m-%d %H:%M'
  local_date_time=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso_timestamp" +'%Y-%m-%d %H:%M')
  local_date=$(echo "$local_date_time" | cut -d' ' -f1)
  local_time=$(echo "$local_date_time" | cut -d' ' -f2)
fi

# Output path
vault_dir="../vault/daily"
vault_path="$vault_dir/$local_date.md"

# Create directory if missing
mkdir -p "$vault_dir"

# If the daily note doesn't exist, create with header
if [[ ! -f "$vault_path" ]]; then
  cat > "$vault_path" <<EOF
# $local_date

## Activity log

EOF
fi

# Compose the entry line
summary_single_line=$(echo "$summary" | tr '\n' ' ')
entry_line="- $local_time — **$project**: $summary_single_line"

# Check for idempotency: if exact entry line already exists, exit 0 (skip)
if grep -F -- "$entry_line" "$vault_path" > /dev/null 2>&1; then
  exit 0
fi

# Append the entry
echo "$entry_line" >> "$vault_path"

# Sort the activity-log section chronologically by HH:MM using Python
python3 - "$vault_path" << 'PYTHON_EOF'
import sys
import re

vault_path = sys.argv[1]

# Read the file
with open(vault_path, 'r') as f:
    lines = f.readlines()

# Find the activity log section
activity_start = -1
activity_end = -1

# Find where "## Activity log" is
for idx, line in enumerate(lines):
    if line.strip() == '## Activity log':
        activity_start = idx
        break

if activity_start >= 0:
    # Find the end of the activity section (next blank line or ## header)
    for idx in range(activity_start + 2, len(lines)):
        if lines[idx].strip() == '' or lines[idx].startswith('##'):
            activity_end = idx
            break

    if activity_end < 0:
        activity_end = len(lines)

    # Extract the activity lines (those starting with "- ")
    activity_lines = []
    other_lines = []

    for idx in range(activity_start + 2, activity_end):
        if lines[idx].startswith('- '):
            activity_lines.append(lines[idx].rstrip('\n'))
        else:
            other_lines.append(lines[idx])

    # Sort activity lines by HH:MM (extract from "- HH:MM — ...")
    def get_time(line):
        match = re.match(r'- (\d{2}:\d{2})', line)
        if match:
            return match.group(1)
        return '00:00'

    activity_lines.sort(key=get_time)

    # Reconstruct the file
    output = lines[:activity_start + 2]  # Header and blank line
    output.extend([line + '\n' for line in activity_lines])
    output.extend(other_lines)
    output.extend(lines[activity_end:])
else:
    output = lines

# Write back
with open(vault_path, 'w') as f:
    f.writelines(output)
PYTHON_EOF

# Print the entry on success
echo "$entry_line"
