---
name: new-project
description: Scaffold a new Claude Code project as a sibling of the orchestrator repo. Use when the operator says "new project <name>", "start a project called X", "spin up X", "scaffold X", or anything equivalent. All projects scaffold with the team template (PM + specialist agents) and auto-launch the PM in tmux. Accepts an optional `--profile mvp|work` to layer a config overlay on top of the base team template (default: `mvp`). Use `--profile work` for paid-client projects that need tighter permissions and work-only MCP connectors (HubSpot, GitHub, ClickUp, Figma).
---

# new-project

Create a new Claude Code project as a sibling directory of the orchestrator
repo. Every project uses the team template — PM + specialist agents, outbox
relay, the whole setup. There is no single-session option.

## Inputs

- `<name>` — project directory name (slug-style, no spaces)
- `--profile <mvp|work>` — optional config overlay (default: `mvp`)
  - `mvp` — loose defaults: `--dangerously-skip-permissions`, all account connectors blocked via `--strict-mcp-config`, permissive Bash/MCP allowlist. Right for personal/experimental projects.
  - `work` — tightened defaults: `--permission-mode auto` (Claude self-vets each tool call, auto-approving safe ones and blocking risky ones), strict-mcp dropped so work connectors load (HubSpot/GitHub/ClickUp/Figma), personal connectors (Telegram/Notion/Gmail/Drive/Calendar/Supabase/Netlify/claude-universe-tools/computer-use/picarx) explicitly denied, `git push` / `npm publish` / destructive ops on the deny list, ssh/scp/rsync denied. Right for paid-client work.

If the operator describes the project context but doesn't name a profile, infer it: client work → `work`, anything else → `mvp`. Confirm with the operator before scaffolding if it's ambiguous.

## Steps

Run from the orchestrator repo root, substituting `<name>` and `<profile>`:

```bash
DEST=../<name>
PROFILE=<profile>   # mvp or work; default mvp
OVERLAY=templates/overlays/$PROFILE

# 1. Base scaffold
mkdir -p "$DEST"
(cd "$DEST" && git init -q)
# Trailing /. copies dotfiles too — do NOT replace with /* or .claude/ is skipped.
cp -R templates/team/. "$DEST"/
# Drop the per-project registry copy — agents/ will symlink to the orchestrator's
# registry in the team-ops launch step (single source of truth).
rm -rf "$DEST"/.claude/agent-registry

# 2. Apply overlay (if the profile has a project/ subtree)
if [ -d "$OVERLAY/project" ]; then
  cp -R "$OVERLAY/project/." "$DEST"/
fi

# 3. Substitute placeholder in every copied file. perl -pi is cross-platform
# (sed -i differs between BSD/macOS and GNU/Linux).
find "$DEST" -type f -not -path '*/.git/*' -exec perl -pi -e "s/\{\{PROJECT_NAME\}\}/<name>/g" {} +
```

Verify: `ls -la ../<name>` and confirm `.claude/agents/` and `CLAUDE.md` are present. For `work` profile, also confirm `.claude/settings.json` contains the deny list (`grep -q '"deny"' "$DEST"/.claude/settings.json && grep -q 'plugin_telegram' "$DEST"/.claude/settings.json`).

Then invoke the `team-ops` skill for the post-scaffold launch steps
(inbox/outbox dirs, initial task file, tmux session, PM kickoff). **Pass the profile through** — `team-ops` reads `templates/overlays/<profile>/launch.flags` to assemble the tmux launch command, so the same flags are not hardcoded in two places.

Report back that the project is ready and that the PM is running in the
`<name>` tmux session. If profile is `work`, additionally remind the operator that they will likely want to set repo-local `git config user.email` to their work address inside any cloned work repos under the project dir — the PM cannot infer it.
