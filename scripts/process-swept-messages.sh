#!/usr/bin/env bash
# Deterministic second half of the outbox sweep.
#
# Consumes the manifest written by sweep-outbox.sh and does, mechanically, what
# the sweeper subagent used to do one model-turn at a time: parse each archived
# message, mirror it to the vault, append the daily-note line, extract and
# canonicalize agent_report ratings into the feedback log (+ vault mirror), and
# run the aggregator if any `done` was processed. Emits a single JSON ledger
# the subagent verifies and reports from.
#
# Design rule #1: NEVER DROP. Anything unparseable or unrecognizable lands in
# quarantined[] / errors[] instead of vanishing. A message the script cannot
# handle degrades to "extra work for the agent", never to silence.
# Design rule #2: the ledger is authored here, not by the model. The subagent's
# job is to verify ledger count == manifest count and pass the result through.
#
# Usage: ./scripts/process-swept-messages.sh   (run from the lilo repo root)
# Env overrides (mainly for tests):
#   MANIFEST      (default /tmp/lilo-sweep-manifest.txt)
#   LEDGER        (default /tmp/lilo-sweep-ledger.json)
#   FEEDBACK_LOG  (default ./agent-feedback.jsonl)
#   NO_VAULT=1    skip vault/daily-note mirroring (tests)
#   NO_AGGREGATE=1 skip the aggregator (tests)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

MANIFEST="${MANIFEST:-/tmp/lilo-sweep-manifest.txt}"
LEDGER="${LEDGER:-/tmp/lilo-sweep-ledger.json}"
FEEDBACK_LOG="${FEEDBACK_LOG:-$REPO_ROOT/agent-feedback.jsonl}"
NO_VAULT="${NO_VAULT:-0}"
NO_AGGREGATE="${NO_AGGREGATE:-0}"

MESSAGES_TMP="$(mktemp)"
QUARANTINE_TMP="$(mktemp)"
QUARANTINE_ENTRIES_TMP="$(mktemp)"
ERRORS_TMP="$(mktemp)"
trap 'rm -f "$MESSAGES_TMP" "$QUARANTINE_TMP" "$QUARANTINE_ENTRIES_TMP" "$ERRORS_TMP"' EXIT

err() { printf '%s\n' "$1" >> "$ERRORS_TMP"; }

manifest_count=0
done_count=0
feedback_appended=0
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [ ! -f "$MANIFEST" ]; then
    err "manifest not found at $MANIFEST — run sweep-outbox.sh first"
else
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        manifest_count=$((manifest_count + 1))

        if [ ! -f "$path" ]; then
            jq -nc --arg p "$path" '{path_archived: $p, reason: "file missing at process time"}' >> "$QUARANTINE_TMP"
            continue
        fi

        if ! content="$(jq -c . "$path" 2>/dev/null)"; then
            # Unparseable JSON: quarantine with the raw text so nothing is lost.
            jq -nc --arg p "$path" --rawfile raw "$path" \
                '{path_archived: $p, reason: "invalid JSON", raw: $raw}' >> "$QUARANTINE_TMP"
            continue
        fi

        project="$(jq -r '.project // "unknown"' <<< "$content")"
        mtype="$(jq -r '.type // "unknown"' <<< "$content")"
        summary="$(jq -r '.summary // ""' <<< "$content")"

        if [ "$NO_VAULT" != "1" ]; then
            if ! ./scripts/mirror-outbox-to-vault.sh "$path" >/dev/null 2>&1; then
                err "vault mirror failed for $path"
            fi
            if ! ./scripts/append-to-daily-note.sh "$project" "$summary" >/dev/null 2>&1; then
                err "daily-note append failed for $path"
            fi
        fi

        # Feedback extraction: done messages with a non-empty agent_report.
        if [ "$mtype" = "done" ]; then
            done_count=$((done_count + 1))
            n_ratings="$(jq '(.agent_report // []) | length' <<< "$content")"
            i=0
            while [ "$i" -lt "$n_ratings" ]; do
                entry="$(jq -c ".agent_report[$i]" <<< "$content")"
                i=$((i + 1))

                # Canonicalize: agent name bare (decorations stripped), rating in
                # {poor, adequate, effective}, note text verbatim whatever the field
                # was called. Numbers map >=5 effective / 3-4 adequate / <=2 poor.
                line="$(jq -c --arg project "$project" --arg ts "$NOW" '
                    def canon_rating:
                        if type == "number" then
                            if . >= 5 then "effective" elif . >= 3 then "adequate" else "poor" end
                        elif type == "string" then
                            (ascii_downcase) as $r
                            | if ["poor","adequate","effective"] | index($r) then $r
                              elif ["good","excellent","great"] | index($r) then "effective"
                              elif ["ok","okay","fair","mixed"] | index($r) then "adequate"
                              elif ["bad","weak","ineffective"] | index($r) then "poor"
                              else null end
                        else null end;
                    {
                        project: $project,
                        timestamp: $ts,
                        agent: ((.agent // .role // "") | gsub("\\s*\\([^)]*\\)"; "") | gsub("^\\s+|\\s+$"; "")),
                        rating: ((.rating // null) | canon_rating),
                        notes: (.notes // .note // "")
                    }' <<< "$entry")"

                agent_name="$(jq -r '.agent' <<< "$line")"
                rating_val="$(jq -r '.rating // "null"' <<< "$line")"
                notes_val="$(jq -r '.notes' <<< "$line")"
                raw_rating="$(jq -r '.rating // "missing"' <<< "$entry")"

                if [ "$raw_rating" = "not-used" ]; then
                    err "rating 'not-used' skipped for '$agent_name' in $path"
                    continue
                fi
                if [ -z "$agent_name" ] || [ "$rating_val" = "null" ]; then
                    jq -nc --arg p "$path" --argjson entry "$entry" \
                        '{path_archived: $p, reason: "unrecognized agent_report entry", entry: $entry}' >> "$QUARANTINE_ENTRIES_TMP"
                    continue
                fi
                if [ -z "$notes_val" ]; then
                    err "agent_report note missing for '$agent_name' in $path"
                fi

                printf '%s\n' "$line" >> "$FEEDBACK_LOG"
                feedback_appended=$((feedback_appended + 1))
                if [ "$NO_VAULT" != "1" ]; then
                    if ! printf '%s\n' "$line" | ./scripts/mirror-feedback-to-vault.sh >/dev/null 2>&1; then
                        err "feedback vault mirror failed for '$agent_name' in $path"
                    fi
                fi
            done
        fi

        jq -nc --arg p "$path" --argjson c "$content" \
            '{path_archived: $p, content: $c}' >> "$MESSAGES_TMP"
    done < "$MANIFEST"
fi

aggregation="null"
if [ "$done_count" -gt 0 ] && [ "$NO_AGGREGATE" != "1" ]; then
    if ! aggregation="$(./.claude/skills/sync/aggregate-feedback.sh 2>/dev/null)" \
        || ! jq -e . >/dev/null 2>&1 <<< "$aggregation"; then
        err "aggregate-feedback.sh failed or returned non-JSON"
        aggregation="null"
    fi
fi

jq -n \
    --slurpfile messages_arr <(cat "$MESSAGES_TMP" 2>/dev/null) \
    --slurpfile quarantine_arr <(cat "$QUARANTINE_TMP" 2>/dev/null) \
    --slurpfile quarantine_entries_arr <(cat "$QUARANTINE_ENTRIES_TMP" 2>/dev/null) \
    --arg manifest_count "$manifest_count" \
    --arg done_count "$done_count" \
    --arg feedback_appended "$feedback_appended" \
    --argjson aggregation "$aggregation" \
    --rawfile errors_raw <(cat "$ERRORS_TMP" 2>/dev/null; printf '') '
    {
        messages: $messages_arr,
        quarantined: $quarantine_arr,
        quarantined_report_entries: $quarantine_entries_arr,
        manifest_count: ($manifest_count | tonumber),
        processed_count: (($messages_arr | length) + ($quarantine_arr | length)),
        done_count: ($done_count | tonumber),
        feedback_lines_appended: ($feedback_appended | tonumber),
        feedback_aggregation: $aggregation,
        errors: ($errors_raw | split("\n") | map(select(. != "")))
    }' > "$LEDGER"

status=0
ledger_ok="$(jq -r 'if .manifest_count == .processed_count then "yes" else "no" end' "$LEDGER")"
if [ "$ledger_ok" != "yes" ]; then
    echo "ERROR: ledger incomplete — manifest $manifest_count, processed $(jq -r '.processed_count' "$LEDGER")" >&2
    status=1
fi

echo "LEDGER=$LEDGER" >&2
echo "MANIFEST_COUNT=$manifest_count" >&2
echo "FEEDBACK_APPENDED=$feedback_appended" >&2
cat "$LEDGER"
exit "$status"
