#!/usr/bin/env bash
# Scan agent-feedback.jsonl for agents meeting the registry-refinement
# thresholds defined in team-ops SKILL.md section 3:
#   - 2+ poor ratings across distinct projects, OR
#   - 4+ adequate ratings (theme inspection happens at the LLM layer)
#
# Emits a single JSON object to stdout:
#   {
#     "flagged": [{ agent, reasons[], poor_count, poor_projects[], adequate_count, adequate_notes[] }, ...],
#     "summary": { agents_seen, flagged_count, total_entries }
#   }
# Always exits 0; if the feed is missing or empty, flagged is [].

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FEED="$ORCHESTRATOR/agent-feedback.jsonl"

if [[ ! -f "$FEED" ]]; then
  echo '{"flagged":[],"summary":{"agents_seen":0,"flagged_count":0,"total_entries":0}}'
  exit 0
fi

jq -s '
  # Canonicalize the agent name before grouping. PMs decorate it with the role or
  # dispatch round -- "frontend (coder)", "frontend (fix-up #2, text-center)" -- and
  # each variant used to group as a SEPARATE agent. That fragmentation hid real
  # signal: frontend`s poor ratings were split across 4 names and never reached a
  # threshold, so the spec was never refined. Strip a trailing parenthetical.
  def canon: sub("\\s*\\(.*\\)\\s*$"; "");

  map(select(.rating == "poor" or .rating == "adequate" or .rating == "effective"))
  | map(. + {agent: (.agent | canon)})
  | . as $all
  | (group_by(.agent) | map({
      agent: .[0].agent,
      total: length,
      poor_count: ([.[] | select(.rating == "poor")] | length),
      poor_projects: ([.[] | select(.rating == "poor") | .project] | unique),
      poor_notes: [.[] | select(.rating == "poor") | {project, notes, timestamp}],
      adequate_count: ([.[] | select(.rating == "adequate")] | length),
      adequate_notes: [.[] | select(.rating == "adequate") | {project, notes, timestamp}],
      effective_count: ([.[] | select(.rating == "effective")] | length)
    })) as $by_agent
  | ($by_agent | map(. + {reasons: (
      # poor>=2 in a SINGLE project still counts. The old rule required >=2 distinct
      # projects, so design-critic sat at 3 poor (all starwood) and never flagged.
      ((if .poor_count >= 2 then ["poor>=2 (" + (.poor_count | tostring) + " in " + ((.poor_projects | length) | tostring) + " project(s))"] else [] end))
      + ((if .adequate_count >= 4 then ["adequate>=4 (" + (.adequate_count | tostring) + ")"] else [] end))
    )})) as $with_reasons
  | {
      flagged: ($with_reasons | map(select(.reasons | length > 0))
        # Worst first: poor ratings outrank a pile of adequates.
        | sort_by(-(.poor_count * 10 + .adequate_count))
        | map({
            agent, reasons, poor_count, poor_projects, poor_notes,
            adequate_count, adequate_notes, effective_count
          })),
      summary: {
        agents_seen: ($by_agent | length),
        flagged_count: ($with_reasons | map(select(.reasons | length > 0)) | length),
        total_entries: ($all | length)
      }
    }
' "$FEED"
