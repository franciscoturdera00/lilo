---
name: new-project
description: Scaffold a new Claude Code project as a sibling of the orchestrator repo. Use when the operator says "new project <name>", "start a project called X", "spin up X", "scaffold X", or anything equivalent. All projects scaffold with the team template (PM + specialist agents) and auto-launch the PM (a Desktop session when Lilo runs in the desktop app, else tmux).
---

# new-project

Create a new Claude Code project as a sibling directory of the orchestrator
repo. Every project uses the team template — PM + specialist agents, outbox
relay, the whole setup. There is no single-session option.

## Inputs

- `<name>` — project directory name (slug-style, no spaces)

There is one project config: the team template, launched in auto permission mode (Claude vets each tool call itself), with every connector available.

## Steps

Run from the orchestrator repo root, substituting `<name>`:

```bash
DEST=../<name>

# 1. Base scaffold
mkdir -p "$DEST"
(cd "$DEST" && git init -q)
# Trailing /. copies dotfiles too — do NOT replace with /* or .claude/ is skipped.
cp -R templates/team/. "$DEST"/
# Drop the per-project registry copy — agents/ will symlink to the orchestrator's
# registry in the team-ops launch step (single source of truth).
rm -rf "$DEST"/.claude/agent-registry

# 2. Substitute placeholder in every copied file. perl -pi is cross-platform
# (sed -i differs between BSD/macOS and GNU/Linux).
find "$DEST" -type f -not -path '*/.git/*' -exec perl -pi -e "s/\{\{PROJECT_NAME\}\}/<name>/g" {} +
```

Verify: `ls -la ../<name>` and confirm `.claude/agents/` and `CLAUDE.md` are present.

Then invoke the `team-ops` skill for the post-scaffold launch steps
(inbox/outbox dirs, initial task file, PM launch and kickoff on the right transport).

Report back that the project is ready and where the PM runs (a link to its
Desktop session, or the `<name>` tmux session). For client work, remind the operator to set repo-local `git config user.email` to their work address inside any cloned work repos under the project dir — the PM cannot infer it.
