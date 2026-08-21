---
name: toolify
description: Package a sibling project into the tools framework so it's callable via the custom MCP bridge. Use when the operator says to toolify a project or asks to expose a project as a tool.
---

# toolify

Package an existing project into the `tools/` framework so its functionality is exposed via the MCP bridge.

**Division of labor:** the project's PM authors the adapter code — it knows the codebase, so it decides what to expose and writes `adapters/` inside its own repo. Lilo owns everything in this repo: the `tools/` symlink, `registry.json`, and the smoke test. Lilo only writes adapters itself when the project has no team scaffold (legacy/imported projects).

## Inputs
- `<project-name>` — name of a sibling directory (at `../<project-name>/` relative to the orchestrator repo)
- Optional: action hints (what functions to expose). If given, pass them through in the PM brief.

## Steps

### 1. Validate the project exists

```bash
ls ../<project-name>/
```

Abort if it doesn't exist. Also check it isn't already toolified:
- Symlink exists at `./tools/<project-name>`
- Entry exists in `tools/registry.json`

If already registered, tell the operator and ask if they want to update the existing registration.

Team-mode markers (`.claude/agents/project-manager.md`, `.team-state.json`) are normal — every scaffolded project has them, and the PM is who builds the adapters. The disqualifier is substance, not structure: check in step 2 whether there's anything to expose.

### 2. Quick recon — is there anything to expose?

Skim the project's `CLAUDE.md` and `README.md`. You need just enough to:
- Confirm the project has real functionality to expose (importable modules, discrete operations)
- Write a one-line description for the brief

**Bail early if there's nothing to expose.** A pure coordination project, a UI with no callable core, a document collection, a scratchpad — not toolifiable. Tell the operator what you found and stop. Do not invent actions just to have something to register.

**Bridge vs native MCP server — decide here.** The bridge suits thin stdlib-friendly wrappers where one shared server beats N processes. A project with heavy deps or its own managed venv (build123d, playwright, torch, ...) is better as a native stdio MCP server run via its own venv (`uv run`), wired directly into `.mcp.json` — tools self-describe, no adapters, no manifest, no bridge restart (cad-workshop went this way in Aug 2026). Recommend the fit to the operator before dispatching; a native-MCP brief asks the PM for a server + launch command instead of the adapter contract, and Lilo's side becomes an `.mcp.json` entry instead of a registry entry.

The detailed action design (which functions, what params) belongs to the PM — do not pre-decide it here beyond relaying the operator's hints.

### 3. Delegate adapter authoring to the PM

If the project has a team scaffold, write a task to `../<project-name>/.lilo-inbox/<timestamp>-toolify.md` containing:

1. The goal: expose this project via Lilo's MCP bridge by adding an `adapters/` package (`__init__.py`, `mcp.py`, `cli.py`), a `tool-manifest.json` at the project root, and, if deps are needed beyond the stdlib, a `requirements.txt`.
2. The operator's action hints, if any.
3. The **full adapter contract** below, verbatim (the PM's specialists don't know the tools framework).
4. The deliverable: `tool-manifest.json` in place (the bridge reads the action list from it — see the contract) plus a `done` message to `.lilo-outbox/`. A `doctor` action is mandatory.
5. Design guidance: bias toward fewer, composable actions — 2-3 focused actions beat 8 granular ones. Import from existing project code; never duplicate logic.
6. The standing rule: from then on, any change to the actions in `adapters/mcp.py` updates `tool-manifest.json` in the same commit — that's how new actions reach the bridge without a Lilo edit. The PM should record this in its own conventions.

Then start the PM if it isn't running (`/pm start <name>`) and nudge it to check its inbox, per `team-ops`.

**No team scaffold?** (Legacy/imported project with no PM.) Author the adapters yourself, following the same contract, then continue at step 5.

### 4. Wait for the PM

The adapter task is small; the PM usually turns it around quickly. Poll `../<project-name>/.lilo-outbox/` for the `done` message for a few minutes. If it's taking longer, tell the operator the adapter work is delegated and stop — the sweep will surface the `done` message, at which point resume from step 5.

### 5. Review the adapters

Read what the PM produced. Sanity checks (do not rewrite style; flag real contract violations back to the PM via inbox):
- Every action function returns `ToolResult` and is wrapped in try/except
- `doctor()` exists and checks real prerequisites
- Params are simple types only (`str`, `int`, `bool`, `list[str]`, `str|None`)
- Logic is imported from project modules, not copy-pasted
- `tool-manifest.json` exists at the project root, parses, and its actions match the functions in `mcp.py`

### 6. Create the symlink

```bash
cd ./tools && ln -s ../../<project-name> <project-name>
```

(From the orchestrator root, the path from `tools/` back to a sibling project is `../../<project-name>`.)

Verify: `readlink <project-name>` and `ls -la <project-name>/adapters/mcp.py`

### 7. Register in registry.json

Read `tools/registry.json`, add a new entry to the `tools` array. The entry is minimal — the bridge reads the action list from the project's `tool-manifest.json` through the symlink, so actions never appear here:

```json
{
  "name": "<project-name>",
  "description": "<one-line description>",
  "path": "<project-name>",
  "adapter": "adapters.mcp"
}
```

(Inline `actions` in a registry entry still work as a fallback for tools without a manifest, e.g. the direct-authoring path may use either.)

### 8. Smoke test

Run doctor via the CLI adapter to verify the wiring works:

```bash
cd ../<project-name> && python -m adapters.cli doctor
```

If it fails, debug: wiring issues on Lilo's side (symlink, registry, bridge venv deps) are yours to fix; defects inside `adapters/` go back to the PM via inbox. Common issues:
- Import paths wrong (sys.path not set up correctly)
- Missing `__init__.py`
- Project uses a venv and imports fail without activation — deps belong in `requirements.txt` so the bridge installs them

### 9. Report

Tell the operator:
- What actions were registered
- The tool name (so they know how to invoke it: `<project-name>.<action>`)
- Any issues found during smoke test
- Note: MCP bridge needs a restart to pick up the new tool (restart happens automatically on next Claude Code session, or the operator can restart manually)

## Adapter contract

Include this whole section in the PM brief. It is also the spec for the no-PM fallback path.

Create `<project>/tool-manifest.json` at the project root — the bridge reads the action list from it at startup:

```json
{
  "description": "<one-line tool description>",
  "actions": [
    {
      "name": "<action>",
      "description": "<what it does>",
      "params": {
        "<param>": {"type": "string", "required": true, "description": "..."}
      },
      "schedule": null
    },
    {
      "name": "doctor",
      "description": "Self-check: verify runtime prerequisites.",
      "params": {},
      "schedule": null
    }
  ]
}
```

An adapter function without a manifest entry is invisible to the bridge; a manifest entry without a matching function fails registration. Keep them in lockstep.

Create `<project>/adapters/` with three files:

**`__init__.py`** — empty

**`mcp.py`** — the MCP adapter. Follow this structure exactly:

```python
"""MCP adapter for <project-name> tool."""

import sys
from pathlib import Path

# When loaded via the MCP bridge, tools/lib is already on sys.path. This block
# handles the CLI entrypoint: walk up from the real adapter location to find
# tools/lib under either the new (inside-orchestrator) or legacy (sibling) layout.
_this = Path(__file__).resolve()
_PROJECT_ROOT = _this.parent.parent
sys.path.insert(0, str(_PROJECT_ROOT))
for _candidate in (
    _this.parents[2] / "tools" / "lib",
    _this.parents[2] / "orchestrator" / "tools" / "lib",
):
    if _candidate.exists():
        sys.path.insert(0, str(_candidate))
        break

from tool_base import ToolResult, setup_logging

# Import from the project's own modules — never duplicate logic
# from <module> import <function>

logger = setup_logging("<project_name>")


def <action>(param: str) -> ToolResult:
    """..."""
    try:
        # Call into existing project code
        return ToolResult(success=True, data={...}, message="...")
    except Exception as e:
        return ToolResult(success=False, data={}, message=str(e))


def doctor() -> ToolResult:
    """Self-check: verify runtime prerequisites."""
    checks = []
    failed = []
    alerts = []

    # Check imports, binaries, data files, auth, etc.

    return ToolResult(
        success=len(failed) == 0,
        data={"checks": checks, "failed": failed},
        message=f"{len(checks) - len(failed)}/{len(checks)} checks passed" if checks else "no checks implemented",
        alerts=alerts,
    )
```

Key rules:
- Every function returns `ToolResult`
- Import from existing project code; never copy-paste logic
- Wrap everything in try/except
- Only simple param types (`str`, `int`, `bool`, `list[str]`, `str|None`)
- `doctor()` is mandatory — check imports, binaries, data files, auth

**`cli.py`** — CLI adapter wrapping the MCP functions via `run_tool()`. Reference template lives at `lilo/tools/templates/cli.py.template` (readable from the project as `../lilo/tools/templates/cli.py.template`). Wire up argparse subcommands matching each action.

**`requirements.txt`** (only if needed) — deps beyond the standard library that the adapter imports need. The bridge auto-installs these on startup. Skip if the project already has one or the adapter imports work without extra deps.

Verify locally before reporting done: `python -m adapters.cli doctor` from the project root.

## Failure handling

- **Project has no importable code** (just scripts with no functions) → thin wrapper functions in `mcp.py` that shell out via `subprocess.run`. Last resort — prefer direct imports. If the project has *nothing* to wrap (no scripts, no functions, no entrypoint), it is not toolifiable; bail per step 2.
- **PM's adapters violate the contract** (missing doctor, complex param types, duplicated logic) → send the specific violations back via `.lilo-inbox/` and wait for the fix. Don't patch the PM's code from here.
- **Circular imports or heavy deps** → isolate imports inside the action functions (lazy import pattern) — include this hint in the brief if the PM hits it.
- **Project already has `adapters/`** → check if it's already toolified. If partially done, brief the PM to complete it rather than overwrite.

## Non-goals
- Lilo does not write into the sibling project when it has a PM — adapter code, fixes to it, and `requirements.txt` all go through the PM. The direct-authoring path exists only for projects with no team scaffold.
- Do not restart the MCP bridge — that's a manual step or happens on next session.
- Do not add the tool to any PM's agent registry — that's a separate decision.
