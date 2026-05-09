---
name: toolify
description: Package a sibling project into the tools framework so it's callable via the custom MCP bridge. Use when the operator says to toolify a project or asks to expose a project as a tool.
---

# toolify

Package an existing project into the `tools/` framework so its functionality is exposed via the MCP bridge.

## Inputs
- `<project-name>` — name of a sibling directory (at `../<project-name>/` relative to the orchestrator repo)
- Optional: action hints (what functions to expose). If omitted, read the project to decide.

## Steps

### 1. Validate the project exists

```bash
ls ../<project-name>/
```

Abort if it doesn't exist. Also check it isn't already toolified:
- Symlink exists at `./tools/<project-name>`
- Entry exists in `tools/registry.json`

If already registered, tell the operator and ask if they want to update the existing registration.

Also check for team-mode markers before going further: if the project has `.claude/agents/project-manager.md` or `.team-state.json`, it is a coordination project (PM + specialists), not a provider. These are almost never toolifiable — surface this to the operator and confirm before continuing.

### 2. Read the project to understand what to expose

Read the project's `CLAUDE.md`, `README.md`, main scripts, and key modules. Identify:
- What the project does (one-line description for registry)
- What discrete actions make sense as MCP tools (each should be a single, useful operation)
- What parameters each action needs (only simple types: `str`, `int`, `bool`, `list[str]`, `str|None`)
- What existing functions to import in the adapter (never duplicate logic)

Bias toward fewer, composable actions. A tool with 2-3 focused actions is better than 8 granular ones. Every tool MUST include a `doctor` action.

**Bail early if there's nothing to expose.** If the project has no importable functions or discrete actions — e.g. it's a team-mode orchestration project, a pure UI, a document collection, or a scratchpad — toolification is not suitable. Tell the operator what you found and stop. Do not try to invent actions or wrap shell scripts just to have something to register.

### 3. Scaffold the adapters

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
- Only simple param types
- `doctor()` is mandatory — check imports, binaries, data files, auth

**`cli.py`** — CLI adapter wrapping the MCP functions via `run_tool()`. Use the template at `tools/templates/cli.py.template` as reference. Wire up argparse subcommands matching each action.

### 4. Add requirements.txt (if needed)

If the project has dependencies beyond the standard library that aren't already in the bridge venv, create `<project>/requirements.txt`. The bridge auto-installs these on startup.

Skip this if the project already has a requirements.txt or manages its own venv and the adapter imports work without extra deps.

### 5. Create the symlink

```bash
cd ./tools && ln -s ../../<project-name> <project-name>
```

(From the orchestrator root, the path from `tools/` back to a sibling project is `../../<project-name>`.)

Verify: `readlink <project-name>` and `ls -la <project-name>/adapters/mcp.py`

### 6. Register in registry.json

Read `tools/registry.json`, add a new entry to the `tools` array:

```json
{
  "name": "<project-name>",
  "description": "<one-line description>",
  "path": "<project-name>",
  "adapter": "adapters.mcp",
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

### 7. Smoke test

Run doctor via the CLI adapter to verify the wiring works:

```bash
cd ../<project-name> && python -m adapters.cli doctor
```

If it fails, debug and fix. Common issues:
- Import paths wrong (sys.path not set up correctly)
- Missing `__init__.py`
- Project uses a venv and imports fail without activation — add deps to requirements.txt so the bridge installs them

### 8. Report

Tell the operator:
- What actions were registered
- The tool name (so they know how to invoke it: `<project-name>.<action>`)
- Any issues found during smoke test
- Note: MCP bridge needs a restart to pick up the new tool (restart happens automatically on next Claude Code session, or the operator can restart manually)

## Failure handling

- **Project has no importable code** (just scripts with no functions) → write thin wrapper functions in `mcp.py` that shell out via `subprocess.run`. This is a last resort — prefer direct imports. If the project has *nothing* to wrap (no scripts, no functions, no entrypoint), it is not toolifiable; bail per Step 2.
- **Team-mode / coordination project** (has `.claude/agents/project-manager.md`, `.team-state.json`, or is otherwise a PM+specialists framework) → not a provider. Do not toolify. Tell the operator and stop.
- **Circular imports or heavy deps** → isolate imports inside the action functions (lazy import pattern).
- **Project already has `adapters/`** → check if it's already toolified. If partially done, complete it rather than overwriting.

## Non-goals
- Do not modify the project's core code. Only add `adapters/` and optionally `requirements.txt`.
- Do not restart the MCP bridge — that's a manual step or happens on next session.
- Do not add the tool to any PM's agent registry — that's a separate decision.
