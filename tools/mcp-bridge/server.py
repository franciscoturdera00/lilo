"""
FastMCP server that dynamically loads and registers tools from the registry.

The server reads registry.json, imports each tool's MCP adapter, and registers
all actions as MCP tools. Parameter schemas are derived from the registry.
"""

import asyncio
import hashlib
import importlib.util
import inspect
import json
import subprocess
import sys
import logging
import functools
from pathlib import Path
from typing import Any

import fastmcp

# Marker dir for tracking which tool requirements.txt files have been installed.
# Stored next to the bridge venv to survive restarts but invalidate on bridge redeploys.
INSTALLED_REQS_DIR = Path(__file__).parent / ".installed_reqs"


def setup_logging(name: str = "mcp_bridge") -> logging.Logger:
    """Configure logging to stderr."""
    logger = logging.getLogger(name)
    logger.setLevel(logging.INFO)
    logger.handlers.clear()

    handler = logging.StreamHandler(sys.stderr)
    formatter = logging.Formatter("[%(name)s] %(levelname)s: %(message)s")
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.propagate = False

    return logger


logger = setup_logging()


def ensure_tool_requirements(tool_name: str, tool_dir: Path) -> None:
    """Lazy-install a tool's requirements.txt into the bridge venv.

    Uses a content-hash marker to skip reinstall when requirements.txt is unchanged.
    Idempotent and safe to call on every bridge startup. No-op if the file is missing.
    """
    req_path = tool_dir / "requirements.txt"
    if not req_path.exists():
        logger.debug(f"{tool_name}: no requirements.txt, skipping lazy install")
        return

    content = req_path.read_bytes()
    digest = hashlib.sha256(content).hexdigest()

    INSTALLED_REQS_DIR.mkdir(parents=True, exist_ok=True)
    marker = INSTALLED_REQS_DIR / f"{tool_name}.hash"

    if marker.exists() and marker.read_text().strip() == digest:
        logger.debug(f"{tool_name}: requirements unchanged, skipping install")
        return

    logger.info(f"{tool_name}: installing requirements.txt into bridge venv")
    try:
        result = subprocess.run(
            [sys.executable, "-m", "pip", "install", "-q", "-r", str(req_path)],
            capture_output=True,
            text=True,
            timeout=300,
        )
        if result.returncode != 0:
            logger.warning(
                f"{tool_name}: pip install failed (rc={result.returncode}): "
                f"{result.stderr.strip()[:500]}"
            )
            return
        marker.write_text(digest)
        logger.info(f"{tool_name}: requirements installed")
    except subprocess.TimeoutExpired:
        logger.warning(f"{tool_name}: pip install timed out after 300s")
    except Exception as e:
        logger.warning(f"{tool_name}: pip install error: {type(e).__name__}: {e}")


def load_registry(registry_path: Path) -> dict:
    """Load and parse registry.json.

    On a fresh clone, registry.json is absent (it's gitignored — see
    registry.example.json for the template). In that case the bridge
    boots with zero tools rather than erroring out.
    """
    if not registry_path.exists():
        example = registry_path.with_name("registry.example.json")
        hint = (
            f" Copy {example.name} to {registry_path.name} and add your tool"
            f" entries."
            if example.exists()
            else ""
        )
        logger.info(
            f"No registry at {registry_path} — starting with zero tools.{hint}"
        )
        return {"tools": []}
    try:
        with open(registry_path, "r") as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Failed to load registry from {registry_path}: {e}")
        return {"tools": []}


def import_tool_adapter(
    tool_name: str, tool_path: Path, registry_dir: Path
) -> Any | None:
    """
    Dynamically import a tool's MCP adapter module.

    Args:
        tool_name: Name of the tool (for logging).
        tool_path: Relative path to the tool (from registry).
        registry_dir: Absolute path to the registry.json directory.

    Returns:
        The imported module, or None if import fails.
    """
    try:
        # Reject paths that escape registry_dir via .. or absolute prefixes.
        # Symlinks inside registry_dir (pointing at sibling projects) are fine —
        # we only block traversal at the registry entry level.
        tp = Path(tool_path)
        if tp.is_absolute() or ".." in tp.parts:
            logger.warning(
                f"Rejected {tool_name!r}: path {tool_path!r} escapes tools/"
            )
            return None

        tool_dir = registry_dir / tool_path
        adapter_path = tool_dir / "adapters" / "mcp.py"

        if not adapter_path.exists():
            logger.warning(
                f"Adapter not found for {tool_name} at {adapter_path}"
            )
            return None

        # Add tool repo root and tools/lib to sys.path temporarily.
        tool_root = tool_dir.parent.parent
        tools_lib = registry_dir / "lib"

        sys.path.insert(0, str(tool_root))
        sys.path.insert(0, str(tools_lib))

        spec = importlib.util.spec_from_file_location(
            f"{tool_name}_mcp", adapter_path
        )
        if spec is None or spec.loader is None:
            logger.warning(f"Could not create spec for {tool_name}")
            return None

        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)

        logger.info(f"Loaded adapter for {tool_name}")
        return module

    except Exception as e:
        logger.warning(
            f"Failed to import adapter for {tool_name}: {type(e).__name__}: {e}"
        )
        return None


def register_tool_action(
    app: fastmcp.FastMCP,
    tool_name: str,
    action_name: str,
    action_spec: dict,
    module: Any,
) -> None:
    """
    Register a single action as an MCP tool.

    Args:
        app: FastMCP application instance.
        tool_name: Name of the tool.
        action_name: Name of the action.
        action_spec: Registry entry for the action.
        module: The imported adapter module.
    """
    try:
        action_fn = getattr(module, action_name, None)
        if action_fn is None:
            logger.warning(
                f"Action {action_name} not found in {tool_name} adapter"
            )
            return

        tool_func_name = f"{tool_name}_{action_name}"

        # Build a dynamic function that wraps the action and preserves its signature.
        def make_handler(fn, tool_n, action_n):
            @functools.wraps(fn)
            def handler(*args, **kwargs):
                try:
                    from tool_base import run_tool
                    result = run_tool(fn, *args, **kwargs)
                    return result.to_dict()
                except Exception as e:
                    logger.error(
                        f"Handler error for {tool_n}.{action_n}: {e}"
                    )
                    return {
                        "success": False,
                        "data": {},
                        "message": f"Handler error: {e}",
                        "alerts": [],
                    }
            handler.__signature__ = inspect.signature(fn)
            return handler

        handler = make_handler(action_fn, tool_name, action_name)

        # Register the tool with FastMCP.
        # FastMCP's tool registration expects a function with type hints.
        # The handler now has the signature of the original function.
        app.tool(
            description=action_spec.get("description", ""),
            name=f"{tool_name}.{action_name}",
        )(handler)

        logger.info(f"Registered tool {tool_name}.{action_name}")

    except Exception as e:
        logger.warning(
            f"Failed to register action {action_name} for {tool_name}: {e}"
        )


def main():
    """Initialize the MCP server and register all tools from the registry."""
    registry_dir = Path(__file__).parent.parent
    registry_path = registry_dir / "registry.json"

    logger.info(f"Loading registry from {registry_path}")
    registry = load_registry(registry_path)

    # Add tools/lib to sys.path so run_tool can be imported
    tools_lib = registry_dir / "lib"
    sys.path.insert(0, str(tools_lib))

    app = fastmcp.FastMCP()

    tools = registry.get("tools", [])
    logger.info(f"Found {len(tools)} tools in registry")

    for tool_entry in tools:
        tool_name = tool_entry.get("name")
        tool_path = tool_entry.get("path")
        actions = tool_entry.get("actions", [])

        if not tool_name or not tool_path:
            logger.warning("Tool entry missing name or path, skipping")
            continue

        logger.info(f"Loading tool {tool_name} from {tool_path}")

        # Lazy-install the tool's requirements.txt into the bridge venv before importing.
        tool_dir_abs = registry_dir / tool_path

        # A tool repo may carry its own action manifest (tool-manifest.json at
        # the repo root, maintained by the project's PM). When present it is
        # the source of truth for the action list — the registry entry then
        # only needs name/path/adapter, and new actions ship with the tool
        # itself. Inline registry actions remain the fallback.
        manifest_path = tool_dir_abs / "tool-manifest.json"
        if manifest_path.exists():
            try:
                with open(manifest_path, "r") as f:
                    manifest = json.load(f)
                manifest_actions = manifest.get("actions", [])
                if manifest_actions:
                    actions = manifest_actions
                    logger.info(
                        f"{tool_name}: {len(actions)} actions from tool-manifest.json"
                    )
                else:
                    logger.warning(
                        f"{tool_name}: tool-manifest.json has no actions; "
                        f"using registry entry"
                    )
            except Exception as e:
                logger.warning(
                    f"{tool_name}: failed to load tool-manifest.json "
                    f"({type(e).__name__}: {e}); using registry entry"
                )

        ensure_tool_requirements(tool_name, tool_dir_abs)

        # Import the adapter module.
        module = import_tool_adapter(tool_name, tool_path, registry_dir)
        if module is None:
            logger.warning(f"Skipping tool {tool_name} due to import failure")
            continue

        # Register each action.
        for action_spec in actions:
            action_name = action_spec.get("name")
            if not action_name:
                logger.warning(f"Action missing name in {tool_name}, skipping")
                continue

            register_tool_action(
                app, tool_name, action_name, action_spec, module
            )

    # Debug: print registered tool schemas to stderr
    try:
        if hasattr(app, '_tools'):
            logger.info("Registered MCP tools with signatures:")
            for tool_name, tool_fn in app._tools.items():
                sig = inspect.signature(tool_fn)
                params_info = {}
                for param_name, param in sig.parameters.items():
                    annotation = param.annotation if param.annotation != inspect.Parameter.empty else "unknown"
                    default = param.default if param.default != inspect.Parameter.empty else "required"
                    params_info[param_name] = {
                        "type": str(annotation),
                        "default": str(default)
                    }
                logger.info(f"  {tool_name}: {json.dumps(params_info)}")
        else:
            logger.warning("Could not access FastMCP._tools for schema inspection")
    except Exception as e:
        logger.warning(f"Could not dump tool schemas: {e}")

    logger.info("MCP server starting")
    app.run(transport="stdio")


if __name__ == "__main__":
    main()
