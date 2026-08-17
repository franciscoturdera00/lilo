#!/usr/bin/env bash
# Regression tests for scripts/process-swept-messages.sh.
#
# Self-contained: builds fixtures in a temp dir, runs the script with env
# overrides (no vault writes, no aggregator, isolated feedback log), asserts
# on the ledger and the feedback lines. Exits non-zero on any failure.
#
# Run from anywhere: ./scripts/tests/test-process-swept-messages.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/process-swept-messages.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
assert() { # assert <description> <actual> <expected>
    if [ "$2" = "$3" ]; then
        echo "ok   - $1"
    else
        echo "FAIL - $1 (got '$2', want '$3')"
        fails=$((fails + 1))
    fi
}

# --- fixtures -----------------------------------------------------------------

cat > "$TMP/m1.json" <<'EOF'
{"type":"done","priority":"normal","project":"projA","summary":"clean done","detail":"d","agent_report":[{"agent":"frontend","rating":"effective","notes":"good work"},{"agent":"code-reviewer","rating":"adequate","notes":"missed one"}]}
EOF

# The messy shapes PMs have actually written: decorated agent names, numeric
# ratings, `note` instead of `notes`, `role` instead of `agent`, alias rating
# words, `not-used`, unrecognized ratings, empty notes.
cat > "$TMP/m2.json" <<'EOF'
{"type":"done","priority":"normal","project":"projB","summary":"messy done","detail":"d","agent_report":[{"agent":"frontend (fix-up #2, text-center)","rating":5,"note":"decorated + numeric + note field"},{"role":"typescript-reviewer (delta)","rating":3,"note":"role field"},{"agent":"scraper","rating":"excellent","notes":"alias rating"},{"agent":"docs","rating":"not-used"},{"agent":"mystery","rating":"banana","notes":"unrecognized rating"},{"agent":"devops","rating":"poor","notes":""}]}
EOF

cat > "$TMP/m3.json" <<'EOF'
{"type":"status","priority":"low","project":"projA","summary":"just status","detail":"d"}
EOF

printf '{broken json!!' > "$TMP/m4.json"

printf '%s\n' "$TMP/m1.json" "$TMP/m2.json" "$TMP/m3.json" "$TMP/m4.json" "$TMP/never-existed.json" > "$TMP/manifest.txt"

# --- run ----------------------------------------------------------------------

MANIFEST="$TMP/manifest.txt" LEDGER="$TMP/ledger.json" FEEDBACK_LOG="$TMP/feedback.jsonl" \
    NO_VAULT=1 NO_AGGREGATE=1 "$SCRIPT" > /dev/null 2>&1
assert "exit 0 on fully-accounted run" "$?" "0"

L="$TMP/ledger.json"
assert "manifest_count"        "$(jq -r '.manifest_count' "$L")" "5"
assert "processed_count == manifest_count" "$(jq -r '.processed_count' "$L")" "5"
assert "parsed messages"       "$(jq -r '.messages | length' "$L")" "3"
assert "quarantined messages (bad JSON + missing file)" "$(jq -r '.quarantined | length' "$L")" "2"
assert "quarantined report entries (banana rating)" "$(jq -r '.quarantined_report_entries | length' "$L")" "1"
assert "done_count"            "$(jq -r '.done_count' "$L")" "2"
assert "feedback lines appended" "$(jq -r '.feedback_lines_appended' "$L")" "6"
assert "errors recorded (not-used skip + empty note)" "$(jq -r '.errors | length' "$L")" "2"
assert "bad JSON quarantine keeps raw text" \
    "$(jq -r '[.quarantined[] | select(.reason == "invalid JSON")] | length' "$L")" "1"

F="$TMP/feedback.jsonl"
assert "feedback log line count"  "$(wc -l < "$F" | tr -d ' ')" "6"
assert "decorated name stripped"  "$(jq -r 'select(.project == "projB" and (.notes | test("decorated"))) | .agent' "$F")" "frontend"
assert "role field accepted"      "$(jq -r 'select(.notes == "role field") | .agent' "$F")" "typescript-reviewer"
assert "numeric 5 -> effective"   "$(jq -r 'select(.notes | test("decorated")) | .rating' "$F")" "effective"
assert "numeric 3 -> adequate"    "$(jq -r 'select(.notes == "role field") | .rating' "$F")" "adequate"
assert "alias excellent -> effective" "$(jq -r 'select(.agent == "scraper") | .rating' "$F")" "effective"
assert "note field carried into notes" "$(jq -r 'select(.agent == "scraper") | .notes' "$F")" "alias rating"
assert "no not-used lines emitted" "$(grep -c 'not-used' "$F")" "0"
assert "no banana lines emitted"   "$(grep -c 'banana' "$F")" "0"

# --- empty manifest -----------------------------------------------------------

: > "$TMP/empty.txt"
MANIFEST="$TMP/empty.txt" LEDGER="$TMP/ledger-empty.json" FEEDBACK_LOG="$TMP/feedback2.jsonl" \
    NO_VAULT=1 NO_AGGREGATE=1 "$SCRIPT" > /dev/null 2>&1
assert "exit 0 on empty manifest" "$?" "0"
assert "empty ledger counts" "$(jq -r '[.manifest_count, .processed_count, (.messages|length)] | join(",")' "$TMP/ledger-empty.json")" "0,0,0"

# --- result -------------------------------------------------------------------

echo
if [ "$fails" -eq 0 ]; then
    echo "PASS: all assertions green"
    exit 0
else
    echo "FAIL: $fails assertion(s) failed"
    exit 1
fi
