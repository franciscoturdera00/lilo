#!/usr/bin/env bash
# Render pipeline.md and pipeline.json at the lilo repo root from the
# current state of every sibling project in the workspace. Idempotent.
# pipeline.json is the structured source for the Notion upsert loop;
# pipeline.md is the human-readable mirror for terminal inspection.

set -euo pipefail

# Resolve paths relative to the script's own location so the script works
# regardless of caller cwd. Layout: <repo>/.claude/skills/sync/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LILO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ROOT="$(cd "$LILO_ROOT/.." && pwd)"
OUT_MD="$LILO_ROOT/pipeline.md"
OUT_JSON="$LILO_ROOT/pipeline.json"

LIVE_SESSIONS="$(tmux ls 2>/dev/null | cut -d: -f1 | sort -u || true)"

declare -a active=() paused=() done_p=() no_state=()

for dir in "$ROOT"/*/; do
  name="$(basename "$dir")"
  case "$name" in
    lilo|orchestrator|scratchpad|logs|tools|vault) continue ;;
  esac
  state="$dir.team-state.json"
  if [[ ! -f "$state" ]]; then
    no_state+=("$name")
    continue
  fi
  status="$(jq -r '.status // "unknown"' "$state" 2>/dev/null || echo unknown)"
  case "$status" in
    active|in_progress) active+=("$name") ;;
    paused|blocked) paused+=("$name") ;;
    done|complete|completed) done_p+=("$name") ;;
    *) active+=("$name") ;;
  esac
done

is_live() {
  local p="$1"
  [[ -n "$LIVE_SESSIONS" ]] && echo "$LIVE_SESSIONS" | grep -qx "$p"
}

count_outbox() {
  find "$1" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' '
}

# ---------- Markdown emitter ----------

render_project_md() {
  local p="$1"
  local state="$ROOT/$p/.team-state.json"
  local phase status updated summary team_count tasks_open
  phase="$(jq -r '.phase // "-" | tostring | .[:40]' "$state" 2>/dev/null || echo '-')"
  status="$(jq -r '.status // "-" | tostring | .[:40]' "$state" 2>/dev/null || echo '-')"
  updated="$(jq -r '.updated_at // "-"' "$state" 2>/dev/null || echo '-')"
  summary="$(jq -r '.summary // ""' "$state" 2>/dev/null || echo '')"
  team_count="$(jq -r '(.team // []) | length' "$state" 2>/dev/null || echo 0)"
  tasks_open="$(jq -r '
    ((.active_tasks // .tasks // [])
      | map(select((.status // "") | test("^(done|complete|completed|completed_with_issues|closed|finished|cancelled|canceled)$") | not))
      | length)' "$state" 2>/dev/null || echo 0)"

  local live="idle"
  is_live "$p" && live="LIVE"

  local outbox_pending outbox_archived
  outbox_pending="$(count_outbox "$ROOT/$p/.lilo-outbox")"
  outbox_archived="$(count_outbox "$ROOT/$p/.lilo-outbox/processed")"

  printf '### %s -- %s (%s)\n' "$p" "$phase" "$status"
  printf '_Updated: %s | PM: %s | Team: %s | Open tasks: %s | Outbox: %s pending / %s archived_\n\n' \
    "$updated" "$live" "$team_count" "$tasks_open" "$outbox_pending" "$outbox_archived"
  if [[ -n "$summary" ]]; then
    printf '%s\n\n' "$summary"
  fi

  local first_task
  first_task="$(jq -r '
    ((.active_tasks // .tasks // [])
      | map(select((.status // "") | test("^(done|complete|completed|completed_with_issues|closed|finished|cancelled|canceled)$") | not))
      | .[0:3]
      | map("- **" + (.id // "?") + "** (" + (.status // "?") + "): " + ((.description // .note // "") | gsub("\n"; " ") | .[:200]))
      | join("\n"))
    // ""' "$state" 2>/dev/null || true)"
  if [[ -n "$first_task" ]]; then
    printf '%s\n\n' "$first_task"
  fi
}

recent_outbox_md() {
  find "$ROOT" -mindepth 4 -maxdepth 4 -path "*/.lilo-outbox/processed/*.json" \
    -not -path "$LILO_ROOT/*" 2>/dev/null \
    | xargs -I{} stat -f "%m %N" {} 2>/dev/null \
    | sort -rn \
    | head -5 \
    | while read -r mtime path; do
        local proj msg ts
        proj="$(echo "$path" | sed -E "s|$ROOT/([^/]+)/.*|\1|")"
        msg="$(jq -r '"\(.type) | \(.summary // "")"' "$path" 2>/dev/null || echo unreadable)"
        ts="$(date -r "$mtime" -u +'%Y-%m-%d %H:%MZ' 2>/dev/null || echo "?")"
        printf -- '- %s -- **%s** %s\n' "$ts" "$proj" "$msg"
      done
}

{
  printf '# Lilo Pipeline\n\n'
  printf '_Updated: %s_\n\n' "$(date -u +'%Y-%m-%d %H:%M UTC')"

  printf 'Projects: %d active, %d paused/blocked, %d done, %d solo (no team-state)\n\n' \
    "${#active[@]}" "${#paused[@]}" "${#done_p[@]}" "${#no_state[@]}"

  if [[ ${#active[@]} -gt 0 ]]; then
    printf '## Active\n\n'
    for p in "${active[@]}"; do render_project_md "$p"; done
  fi

  if [[ ${#paused[@]} -gt 0 ]]; then
    printf '## Paused / Blocked\n\n'
    for p in "${paused[@]}"; do render_project_md "$p"; done
  fi

  if [[ ${#done_p[@]} -gt 0 ]]; then
    printf '## Done\n\n'
    for p in "${done_p[@]}"; do render_project_md "$p"; done
  fi

  if [[ ${#no_state[@]} -gt 0 ]]; then
    printf '## Solo projects (no team-state)\n\n'
    for p in "${no_state[@]}"; do printf -- '- %s\n' "$p"; done
    printf '\n'
  fi

  printf '## Recent outbox activity (last 5 archived messages)\n\n'
  out="$(recent_outbox_md)"
  if [[ -z "$out" ]]; then
    printf '_No archived outbox messages._\n'
  else
    printf '%s\n' "$out"
  fi
} > "$OUT_MD"

# ---------- JSON emitter ----------

project_json() {
  local p="$1"
  local state="$ROOT/$p/.team-state.json"
  local pm_live=false
  is_live "$p" && pm_live=true

  local outbox_pending outbox_archived
  outbox_pending="$(count_outbox "$ROOT/$p/.lilo-outbox")"
  outbox_archived="$(count_outbox "$ROOT/$p/.lilo-outbox/processed")"

  if [[ ! -f "$state" ]]; then
    jq -n \
      --arg name "$p" \
      --arg local_path "$ROOT/$p/" \
      --argjson pm_live "$pm_live" \
      --argjson outbox_pending "$outbox_pending" \
      --argjson outbox_archived "$outbox_archived" \
      '{
        name: $name,
        local_path: $local_path,
        has_state: false,
        status: "solo",
        pm_live: $pm_live,
        outbox_pending: $outbox_pending,
        outbox_archived: $outbox_archived
      }'
    return
  fi

  jq \
    --arg name "$p" \
    --arg local_path "$ROOT/$p/" \
    --argjson pm_live "$pm_live" \
    --argjson outbox_pending "$outbox_pending" \
    --argjson outbox_archived "$outbox_archived" \
    '{
      name: $name,
      local_path: $local_path,
      has_state: true,
      pm_live: $pm_live,
      outbox_pending: $outbox_pending,
      outbox_archived: $outbox_archived,
      status: (.status // "unknown"),
      phase: (.phase // null),
      updated_at: (.updated_at // null),
      summary: (.summary // ""),
      context: (.context // ""),
      team: (.team // []),
      team_size: ((.team // []) | length),
      open_decisions: (.open_decisions // []),
      v2_scope: (.v2_scope // []),
      active_tasks: (
        (.active_tasks // .tasks // [])
        | map(select((.status // "") | test("^(done|complete|completed|completed_with_issues|closed|finished|cancelled|canceled)$") | not))
      ),
      open_tasks_count: (
        (.active_tasks // .tasks // [])
        | map(select((.status // "") | test("^(done|complete|completed|completed_with_issues|closed|finished|cancelled|canceled)$") | not))
        | length
      )
    }' "$state" 2>/dev/null || jq -n --arg name "$p" '{name: $name, has_state: false, status: "unparseable"}'
}

recent_outbox_json() {
  find "$ROOT" -mindepth 4 -maxdepth 4 -path "*/.lilo-outbox/processed/*.json" \
    -not -path "$LILO_ROOT/*" 2>/dev/null \
    | xargs -I{} stat -f "%m %N" {} 2>/dev/null \
    | sort -rn \
    | head -10 \
    | while read -r mtime path; do
        local proj ts
        proj="$(echo "$path" | sed -E "s|$ROOT/([^/]+)/.*|\1|")"
        ts="$(date -r "$mtime" -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "")"
        jq -c \
          --arg proj "$proj" \
          --arg ts "$ts" \
          '{timestamp: $ts, project: $proj, type: (.type // ""), priority: (.priority // ""), summary: (.summary // "")}' \
          "$path" 2>/dev/null || true
      done | jq -s '.'
}

projects_arr="$(
  {
    for p in "${active[@]}"; do project_json "$p"; done
    for p in "${paused[@]}"; do project_json "$p"; done
    for p in "${done_p[@]}"; do project_json "$p"; done
    for p in "${no_state[@]}"; do project_json "$p"; done
  } | jq -s '.'
)"

recent_arr="$(recent_outbox_json)"

live_pms_arr="$(printf '%s\n' "${LIVE_SESSIONS}" | jq -R . | jq -s 'map(select(length > 0))')"

jq -n \
  --arg generated_at "$(date -u +%FT%TZ)" \
  --argjson active "${#active[@]}" \
  --argjson paused "${#paused[@]}" \
  --argjson done "${#done_p[@]}" \
  --argjson solo "${#no_state[@]}" \
  --argjson live_pms "$live_pms_arr" \
  --argjson projects "$projects_arr" \
  --argjson recent_activity "$recent_arr" \
  '{
    generated_at: $generated_at,
    snapshot: {
      active: $active,
      paused: $paused,
      done: $done,
      solo: $solo,
      live_pms: $live_pms
    },
    projects: $projects,
    recent_activity: $recent_activity
  }' > "$OUT_JSON"

echo "$OUT_MD"
echo "$OUT_JSON"
