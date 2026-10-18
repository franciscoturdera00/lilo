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

# --- manifest path handling + files[] -----------------------------------------

"$SCRIPT" > /dev/null 2>&1
assert "exit 2 with no manifest given" "$?" "2"

mkdir -p "$TMP/run" "$TMP/projC/.lilo-outbox/processed"
touch "$TMP/projC/real.png" "$TMP/outside.txt"
cat > "$TMP/projC/.lilo-outbox/processed/m5.json" <<EOF
{"type":"done","priority":"high","project":"projC","summary":"with files","detail":"d","id":"m5","files":["$TMP/projC/real.png","$TMP/projC/ghost.png","$TMP/outside.txt"]}
EOF
printf '%s\n' "$TMP/projC/.lilo-outbox/processed/m5.json" > "$TMP/run/manifest.txt"
FEEDBACK_LOG="$TMP/feedback3.jsonl" NO_VAULT=1 NO_AGGREGATE=1 \
    "$SCRIPT" "$TMP/run/manifest.txt" > /dev/null 2>&1
assert "exit 0 with positional manifest" "$?" "0"
R="$TMP/run/ledger.json"
assert "ledger defaults next to manifest" "$([ -f "$R" ] && echo yes)" "yes"
assert "ledger records manifest_path" "$(jq -r '.manifest_path' "$R")" "$TMP/run/manifest.txt"
assert "files passed through in content" "$(jq -r '.messages[0].content.files | length' "$R")" "3"
assert "missing files entry reported" "$(jq -r '[.errors[] | select(test("ghost.png"))] | length' "$R")" "1"
assert "in-project files entry not reported" "$(jq -r '[.errors[] | select(test("real.png"))] | length' "$R")" "0"
assert "outside-project files entry reported" "$(jq -r '[.errors[] | select(test("outside project.*outside.txt"))] | length' "$R")" "1"

# --- sweep-outbox.sh: per-run manifest, in a throwaway workspace ---------------
# Copy the script into a fake workspace so it never touches real outboxes.

WS="$TMP/ws"
mkdir -p "$WS/lilo/scripts" "$WS/projX/.lilo-outbox/processed"
cp "$REPO_ROOT/scripts/sweep-outbox.sh" "$WS/lilo/scripts/"
echo '{"type":"status"}' > "$WS/projX/.lilo-outbox/a.json"
echo '{"type":"status"}' > "$WS/projX/.lilo-outbox/processed/old.json"

out1="$(cd "$WS/lilo" && TMPDIR="$TMP" ./scripts/sweep-outbox.sh 2>&1 >/dev/null)"
assert "sweep exit 0" "$?" "0"
m1="$(sed -n 's/^MANIFEST=//p' <<< "$out1")"
is_run_path=no
[[ "$m1" == "$TMP"/lilo-sweep.*/manifest.txt ]] && is_run_path=yes
assert "default manifest is a per-run mktemp path" "$is_run_path" "yes"
assert "manifest lists the one pending message" "$(wc -l < "$m1" | tr -d ' ')" "1"

out2="$(cd "$WS/lilo" && TMPDIR="$TMP" ./scripts/sweep-outbox.sh 2>&1 >/dev/null)"
m2="$(sed -n 's/^MANIFEST=//p' <<< "$out2")"
assert "empty sweep still prints MANIFEST" "$([ -n "$m2" ] && echo yes)" "yes"
assert "second run gets a different manifest" "$([ "$m1" != "$m2" ] && echo yes)" "yes"
assert "first run's manifest untouched by second" "$(wc -l < "$m1" | tr -d ' ')" "1"

out3="$(cd "$WS/lilo" && MANIFEST="$TMP/explicit.txt" ./scripts/sweep-outbox.sh 2>&1 >/dev/null)"
assert "explicit MANIFEST honored" "$(sed -n 's/^MANIFEST=//p' <<< "$out3")" "$TMP/explicit.txt"

# PROJECT filter: only the named sibling is swept.
mkdir -p "$WS/projY/.lilo-outbox"
echo '{"type":"status"}' > "$WS/projX/.lilo-outbox/b.json"
echo '{"type":"status"}' > "$WS/projY/.lilo-outbox/c.json"
out4="$(cd "$WS/lilo" && PROJECT=projY MANIFEST="$TMP/proj.txt" ./scripts/sweep-outbox.sh 2>&1 >/dev/null)"
assert "PROJECT sweep exit 0" "$?" "0"
assert "PROJECT sweep took only projY" "$(cat "$TMP/proj.txt")" "../projY/.lilo-outbox/processed/c.json"
assert "other project left pending" "$([ -f "$WS/projX/.lilo-outbox/b.json" ] && echo yes)" "yes"
(cd "$WS/lilo" && PROJECT=../etc MANIFEST="$TMP/bad.txt" ./scripts/sweep-outbox.sh >/dev/null 2>&1)
assert "PROJECT with a slash rejected" "$?" "1"
rm -f "$TMP/bad.txt"
(cd "$WS/lilo" && PROJECT=nope MANIFEST="$TMP/bad.txt" ./scripts/sweep-outbox.sh >/dev/null 2>&1)
assert "unknown PROJECT rejected" "$?" "1"
assert "rejected PROJECT leaves no manifest" "$([ -e "$TMP/bad.txt" ] && echo exists || echo none)" "none"
(cd "$WS/lilo" && PROJECT=lilo MANIFEST="$TMP/bad.txt" ./scripts/sweep-outbox.sh >/dev/null 2>&1)
assert "PROJECT=lilo (self) rejected" "$?" "1"

# --- result -------------------------------------------------------------------

echo
if [ "$fails" -eq 0 ]; then
    echo "PASS: all assertions green"
    exit 0
else
    echo "FAIL: $fails assertion(s) failed"
    exit 1
fi
