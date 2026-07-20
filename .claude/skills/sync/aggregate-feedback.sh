#!/usr/bin/env bash
# Scan agent-feedback.jsonl for agents meeting the registry-refinement thresholds
# defined in team-ops SKILL.md section 3, RECENCY-WEIGHTED so resolved historical
# clusters stop crying wolf.
#
# Each rating is decayed by age with a half-life (default 45 days): a rating given
# today weighs 1.0, one a half-life ago weighs 0.5, two half-lives 0.25, etc. Age is
# measured against ref = max(newest rating in the feed, wall-clock now) so ages are
# never negative (no weight blow-up under clock skew) yet still decay in real time
# when the clock is sane. Thresholds then apply to the WEIGHTED sums:
#   - weighted poor >= 2.0   (a recency-equivalent of "2 recent poor ratings"), OR
#   - weighted adequate >= 4.0
# Raw counts + newest-first notes are still emitted so the LLM layer sees both the
# decayed signal and the underlying history.
#
# Emits a single JSON object to stdout:
#   {
#     "flagged": [{ agent, reasons[], poor_count, wpoor, poor_projects[], poor_notes[],
#                   adequate_count, wadequate, adequate_notes[], effective_count,
#                   last_poor, last_seen }, ...],
#     "summary": { agents_seen, flagged_count, total_entries, half_life_days, ref_date }
#   }
# Always exits 0; if the feed is missing or empty, flagged is [].

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATOR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FEED="$ORCHESTRATOR/agent-feedback.jsonl"

HALF_LIFE_DAYS="${FEEDBACK_HALF_LIFE_DAYS:-45}"

if [[ ! -f "$FEED" ]]; then
  echo '{"flagged":[],"summary":{"agents_seen":0,"flagged_count":0,"total_entries":0,"half_life_days":'"$HALF_LIFE_DAYS"',"ref_date":null}}'
  exit 0
fi

jq -s --argjson half "$HALF_LIFE_DAYS" '
  # Canonicalize the agent name before grouping. PMs decorate it with the role or
  # dispatch round -- "frontend (coder)", "frontend (fix-up #2, text-center)" -- and
  # each variant used to group as a SEPARATE agent. That fragmentation hid real
  # signal: frontend`s poor ratings were split across 4 names and never reached a
  # threshold, so the spec was never refined. Strip a trailing parenthetical.
  def canon: sub("\\s*\\(.*\\)\\s*$"; "");
  # Some entries use "note", others "notes". Read either.
  def notetext: (.notes // .note);
  # Parse an ISO8601 timestamp to epoch seconds; null if absent/malformed.
  def parse_ts: (. // "" | (try fromdateiso8601 catch null));
  def round2: (. * 100 | round) / 100;

  map(select(.rating == "poor" or .rating == "adequate" or .rating == "effective"))
  | map(. + {agent: (.agent | canon), _ts: (.timestamp | parse_ts)})
  | . as $all
  # Reference "now": the later of the newest rating and the wall clock, so an entry
  # is never in the future relative to ref (weight would otherwise exceed 1).
  | (([$all[]._ts | select(. != null)] + [now]) | max) as $ref
  # Half-life decay. log(0.5) is negative, so older -> smaller weight. Undated
  # ratings (no parseable timestamp) get a small floor so they still register faintly.
  | def wt($ts):
      if $ts == null then 0.15
      else ((($ref - $ts) / 86400) as $age0
            | (if $age0 < 0 then 0 else $age0 end) as $age
            | (($age / $half) * (0.5 | log) | exp)) end;
  map(. + {_w: wt(._ts)})
  | (group_by(.agent) | map({
      agent: .[0].agent,
      total: length,
      poor_count: ([.[] | select(.rating == "poor")] | length),
      wpoor: (([.[] | select(.rating == "poor") | ._w] | add // 0) | round2),
      poor_projects: ([.[] | select(.rating == "poor") | .project] | unique),
      poor_notes: ([.[] | select(.rating == "poor")
                    | {project, notes: notetext, timestamp, w: (._w | round2)}]
                   | sort_by(.timestamp) | reverse),
      adequate_count: ([.[] | select(.rating == "adequate")] | length),
      wadequate: (([.[] | select(.rating == "adequate") | ._w] | add // 0) | round2),
      adequate_notes: ([.[] | select(.rating == "adequate")
                        | {project, notes: notetext, timestamp, w: (._w | round2)}]
                       | sort_by(.timestamp) | reverse),
      effective_count: ([.[] | select(.rating == "effective")] | length),
      weffective: (([.[] | select(.rating == "effective") | ._w] | add // 0) | round2),
      last_poor: ([.[] | select(.rating == "poor") | .timestamp] | max),
      last_seen: ([.[] | .timestamp] | max)
    })) as $by_agent
  | ($by_agent | map(. + {reasons: (
      ((if .wpoor >= 2 then ["poor weighted " + (.wpoor | tostring)
          + " (raw " + (.poor_count | tostring) + " across "
          + ((.poor_projects | length) | tostring) + " project(s), newest " + (.last_poor // "?") + ")"] else [] end))
      + ((if .wadequate >= 4 then ["adequate weighted " + (.wadequate | tostring)
          + " (raw " + (.adequate_count | tostring) + ")"] else [] end))
    )})) as $with_reasons
  | {
      flagged: ($with_reasons | map(select(.reasons | length > 0))
        # Worst first: recency-weighted poor outranks a pile of decayed adequates.
        | sort_by(-(.wpoor * 10 + .wadequate))
        | map({
            agent, reasons, poor_count, wpoor, poor_projects, poor_notes,
            adequate_count, wadequate, adequate_notes, effective_count, weffective,
            last_poor, last_seen
          })),
      summary: {
        agents_seen: ($by_agent | length),
        flagged_count: ($with_reasons | map(select(.reasons | length > 0)) | length),
        total_entries: ($all | length),
        half_life_days: $half,
        ref_date: ($ref | todateiso8601)
      }
    }
' "$FEED"
