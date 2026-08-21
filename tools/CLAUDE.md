# tools — Framework for Claude Universe utilities

## Overview

This directory provides the framework for building pluggable tool adapters that expose functionality to Claude agents via MCP (Model Context Protocol) and CLI interfaces.

## Directory structure

- `lib/` — Shared utilities: `tool_base.py` (ToolResult, logging, exception wrapping)
- `templates/` — Reference templates for building new tool adapters (`cli.py.template`, `mcp.py.template`)
- `mcp-bridge/` — MCP server implementation; reads registry.json and dynamically imports adapter modules
- `registry.json` — Registry of all available tools, their actions, and parameters
- Tool symlinks / dirs — Each tool is symlinked into this directory (pointing at a sibling project repo) or lives directly under `tools/<name>/`

## Adding a new tool

### 1. Create adapter module + manifest in the tool repo

Under `<tool>/adapters/`:

- `__init__.py` — Empty file (creates package)
- `mcp.py` — Expose tool functions returning ToolResult
- `cli.py` — CLI wrapper with argparse subcommands dispatching to mcp.py via run_tool()

At `<tool>/tool-manifest.json` (repo root), the action manifest — owned by the tool repo, read by the bridge at startup:

```json
{
  "description": "Tool description",
  "actions": [
    {
      "name": "my_action",
      "description": "Action description",
      "params": {
        "input": {"type": "string", "required": true, "description": "Input parameter"}
      },
      "schedule": null
    }
  ]
}
```

Any change to the actions in `mcp.py` must update `tool-manifest.json` in the same commit: an adapter function without a manifest entry is invisible to the bridge; a manifest entry without a matching function fails registration.

### 2. Symlink into tools/

From the orchestrator root, point at a sibling project:
```bash
cd tools && ln -s ../../my-tool my-tool
```

Verify with `readlink my-tool` and `ls -la my-tool`.

### 3. Add registry entry

Edit `registry.json` and add a tool object with:
- `name` — Unique tool identifier
- `description` — Human-readable description
- `path` — Relative path from tools/ (matches symlink name)
- `adapter` — Module path to MCP adapter (e.g., `adapters.mcp`)

Example:
```json
{
  "name": "my-tool",
  "description": "Tool description",
  "path": "my-tool",
  "adapter": "adapters.mcp"
}
```

The registry decides *which* tools are on the bridge; each tool's `tool-manifest.json` decides *what* it exposes. A registry entry may instead carry an inline `actions` array (same schema as the manifest) — used as a fallback when the tool has no `tool-manifest.json`; when both exist the manifest wins.

## Implementation conventions

### Required: `doctor()` action on every tool

Every tool's `adapters/mcp.py` MUST export a `doctor()` function that returns a ToolResult. This is a self-check action that verifies the tool's runtime prerequisites:

- External binaries in PATH (CLI tools, renderers)
- API keys or auth resolvable from env/config
- Required data files present and parseable
- Heavy Python imports succeed (playwright, python-docx, etc.)

`doctor()` takes no parameters, must complete in under 5 seconds, and must be side-effect-free (no disk writes, no destructive ops, no expensive network calls beyond what's needed to verify auth).

On success, return:
```python
ToolResult(success=True, data={"checks": [{"name": "...", "ok": True, "detail": "..."}]}, message="N/M checks passed")
```

On failure, populate `data["failed"]` with the names of failed checks and use `alerts[]` for anything Lilo should surface to the operator via Telegram (e.g., "claude CLI not logged in").

Every tool must also register `doctor` in its `tool-manifest.json` (or the registry fallback):
```json
{
  "name": "doctor",
  "description": "Self-check: verify runtime prerequisites (binaries, auth, data files).",
  "params": {},
  "schedule": null
}
```

Lilo invokes `<tool>.doctor` on demand and on a schedule to catch breakage before users hit it. See `templates/mcp.py.template` for a starter implementation.

### ToolResult

All adapter functions must return `ToolResult(success, data, message, alerts)`. Use:
```python
from tool_base import ToolResult

return ToolResult(
    success=True,
    data={"key": "value"},
    message="One-line summary"
)
```

### Parameter types

Accept only simple types: `str`, `int`, `bool`, `list[str]`, `str|None`. No dicts, objects, or complex types.

### Error handling

Never let exceptions propagate. Always wrap function bodies in try/except:
```python
try:
    # work
    return ToolResult(success=True, ...)
except Exception as e:
    return ToolResult(success=False, message=str(e))
```

Or use the `run_tool()` wrapper at the CLI boundary:
```python
result = run_tool(adapter_function, *args, **kwargs)
print(result.to_json())
```

### Logging

Use `setup_logging()` and log to stderr only (stdout is reserved for JSON output):
```python
from tool_base import setup_logging

logger = setup_logging("module_name")
logger.info("Human-readable message")
```

### Imports

When loaded through the MCP bridge, `tools/lib` is already on sys.path — no extra setup needed. For the CLI entrypoint, the template in `templates/mcp.py.template` walks up from the adapter file to find `tools/lib` under either `orchestrator/tools/` (in-repo layout) or as a sibling `tools/` dir (legacy layout). Copy that block at the top of new adapters.

```python
from tool_base import ToolResult
```

### Code reuse

Adapter functions call INTO existing code via imports. Do not copy/paste logic:
```python
# Good
from my_module import existing_function
def my_adapter(input: str) -> ToolResult:
    result = existing_function(input)
    return ToolResult(...)

# Bad
def my_adapter(input: str) -> ToolResult:
    # [duplicate implementation]
```

## Scheduling

Tool scheduling is orthogonal to this framework. Any tool CLI can be scheduled by an external scheduler:

- **macOS**: Use `launchd` (native) or Claude Code's `schedule` skill (agent-level triggers)
- **Linux**: Use systemd timers or cron
- **Cron**: Avoid on macOS (requires caffeinate; prefer launchd)

The `schedule` field in registry.json is informational metadata documenting intended cadence — it is not read or processed by this framework. See `SCHEDULING.md` for details.

## References

- `tool_base.py` — ToolResult dataclass and run_tool() wrapper
- `registry.json` — Current tool inventory and action schemas
- `SCHEDULING.md` — Notes on scheduling and cadence
