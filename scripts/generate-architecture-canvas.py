#!/usr/bin/env python3
"""
Generate an Obsidian Canvas showing Lilo's runtime architecture.

Reads:
  - templates/team/.claude/agent-registry/*.md  (PM specialists)
  - .claude/agents/{outbox-sweeper,pipeline-syncer,stitch-operator}.md
    (orchestrator-only subagents)
  - .mcp.json  (project MCP servers)
  - pipeline.json  (optional, live project state)

Outputs:
  ../vault/architecture.canvas  (JSON)

Layout: Lilo at top, four group-boxed clusters below — PM specialists,
orchestrator-only subagents, MCPs, and live projects (if pipeline.json is
present). A handful of MCP-to-specialist edges highlight the most-coupled
relationships without cluttering the graph.
"""

import json
import re
from pathlib import Path


# ─── Visual constants ─────────────────────────────────────────────────

NODE_W = 260
NODE_H = 92
ROW_PITCH = 170
GROUP_PAD = 60
LILO_W = 460
LILO_H = 160

# Cluster x-lanes (disjoint, with breathing room for group padding)
PM_X      = [-1180, -880, -580]          # 3 columns
ORCH_X    = -200
MCP_X     = 160
PROJECT_X = 520

GRID_Y = 420                              # where the per-cluster grids start
LABEL_Y = 200                             # category label band


# ─── Source readers ───────────────────────────────────────────────────

def scan_registry():
    """Return sorted list of (name, description) tuples for PM specialists."""
    registry_dir = Path("templates/team/.claude/agent-registry")
    agents = []
    if not registry_dir.exists():
        return agents
    for md in sorted(registry_dir.glob("*.md")):
        if md.name == "README.md":
            continue
        agents.append((md.stem, ""))
    return agents


def get_orchestrator_only_agents():
    agents_dir = Path(".claude/agents")
    targets = ["outbox-sweeper", "pipeline-syncer", "stitch-operator"]
    out = []
    for t in targets:
        if (agents_dir / f"{t}.md").exists():
            out.append(t)
    return out


def get_mcps():
    """List of (name, description) for project + summary MCPs."""
    mcps = []
    try:
        with open(".mcp.json") as f:
            servers = json.load(f).get("mcpServers", {})
            for name in ["lilo-tools", "playwright", "ios-simulator", "picarx"]:
                if name in servers:
                    mcps.append((name, ""))
    except Exception:
        pass
    mcps.append(("account-level MCPs",
                 "Notion · Figma · Gmail · Calendar\nGitHub · HubSpot · ClickUp · Supabase"))
    return mcps


def get_projects():
    """Read pipeline.json and return list of dicts. Empty list if missing."""
    pipeline = Path("pipeline.json")
    if not pipeline.exists():
        return []
    try:
        data = json.loads(pipeline.read_text())
        return data.get("projects", [])
    except Exception:
        return []


# ─── Canvas builder ───────────────────────────────────────────────────

def status_color(status):
    """Obsidian color code per project status."""
    status = (status or "").lower()
    if status in ("blocked",):                 return "1"  # red
    if status in ("paused",):                  return "3"  # yellow
    if status in ("done", "complete",
                  "completed", "closed"):      return "6"  # purple
    if status in ("active", "in_progress"):    return "4"  # green
    return "5"                                              # cyan (solo)


def build_canvas():
    nodes = []
    edges = []
    counter = [0]

    def nid():
        counter[0] += 1
        return f"n{counter[0]}"

    # ─── Group nodes drawn FIRST so they sit behind their children ──

    registry_agents = scan_registry()
    orch_agents = get_orchestrator_only_agents()
    mcps = get_mcps()
    projects = get_projects()

    pm_rows = (len(registry_agents) + 2) // 3
    orch_rows = max(len(orch_agents), 1)
    mcp_rows = max(len(mcps), 1)
    project_rows = max(len(projects), 1)

    # Compute each cluster's total grid height
    pm_height = pm_rows * ROW_PITCH
    orch_height = orch_rows * ROW_PITCH
    mcp_height = mcp_rows * ROW_PITCH
    project_height = project_rows * ROW_PITCH

    # Group node for PM cluster — spans all 3 cols
    pm_group_id = nid()
    nodes.append({
        "id": pm_group_id,
        "type": "group",
        "label": "PM Template — Specialists",
        "x": PM_X[0] - GROUP_PAD,
        "y": LABEL_Y - GROUP_PAD,
        "width": (PM_X[-1] + NODE_W) - PM_X[0] + 2 * GROUP_PAD,
        "height": (GRID_Y + pm_height) - LABEL_Y + GROUP_PAD,
        "color": "4"
    })

    orch_group_id = nid()
    nodes.append({
        "id": orch_group_id,
        "type": "group",
        "label": "Lilo's Subagents",
        "x": ORCH_X - GROUP_PAD,
        "y": LABEL_Y - GROUP_PAD,
        "width": NODE_W + 2 * GROUP_PAD,
        "height": (GRID_Y + orch_height) - LABEL_Y + GROUP_PAD,
        "color": "2"
    })

    mcp_group_id = nid()
    nodes.append({
        "id": mcp_group_id,
        "type": "group",
        "label": "MCPs & Connectors",
        "x": MCP_X - GROUP_PAD,
        "y": LABEL_Y - GROUP_PAD,
        "width": NODE_W + 2 * GROUP_PAD,
        "height": (GRID_Y + mcp_height) - LABEL_Y + GROUP_PAD,
        "color": "3"
    })

    project_group_id = None
    if projects:
        project_group_id = nid()
        nodes.append({
            "id": project_group_id,
            "type": "group",
            "label": "Active Projects (live state)",
            "x": PROJECT_X - GROUP_PAD,
            "y": LABEL_Y - GROUP_PAD,
            "width": NODE_W + 2 * GROUP_PAD,
            "height": (GRID_Y + project_height) - LABEL_Y + GROUP_PAD,
            "color": "6"
        })

    # ─── Lilo node — bigger, with tagline ─────────────────────────

    lilo_id = "lilo"
    lilo_x = (PM_X[0] + (PROJECT_X + NODE_W)) // 2 - LILO_W // 2
    nodes.append({
        "id": lilo_id,
        "type": "text",
        "text": (
            "# Lilo\n"
            "*the orchestrator*\n\n"
            "Talks to the operator on Telegram + terminal. Scaffolds PMs in tmux. "
            "Dispatches subagents. Syncs Notion + vault. Owns this repo only."
        ),
        "x": lilo_x,
        "y": 0,
        "width": LILO_W,
        "height": LILO_H,
        "color": "5"
    })

    # ─── PM specialists grid ─────────────────────────────────────

    pm_agent_ids = {}
    for idx, (name, _desc) in enumerate(registry_agents):
        col = idx % 3
        row = idx // 3
        node_id = nid()
        pm_agent_ids[name] = node_id
        nodes.append({
            "id": node_id,
            "type": "file",
            "file": f"agents/{name}.md",
            "x": PM_X[col],
            "y": GRID_Y + row * ROW_PITCH,
            "width": NODE_W,
            "height": NODE_H,
            "color": "4"
        })

    # ─── Orchestrator-only subagents ─────────────────────────────

    orch_agent_ids = {}
    for idx, name in enumerate(orch_agents):
        node_id = nid()
        orch_agent_ids[name] = node_id
        nodes.append({
            "id": node_id,
            "type": "text",
            "text": f"# {name}\n*orchestrator-only*\nhaiku · scoped",
            "x": ORCH_X,
            "y": GRID_Y + idx * ROW_PITCH,
            "width": NODE_W,
            "height": NODE_H + 18,
            "color": "2"
        })

    # ─── MCPs ────────────────────────────────────────────────────

    mcp_ids = {}
    for idx, (name, desc) in enumerate(mcps):
        text = f"# {name}"
        if desc:
            text += f"\n{desc}"
        node_id = nid()
        mcp_ids[name] = node_id
        nodes.append({
            "id": node_id,
            "type": "text",
            "text": text,
            "x": MCP_X,
            "y": GRID_Y + idx * ROW_PITCH,
            "width": NODE_W,
            "height": NODE_H + (22 if desc else 0),
            "color": "3"
        })

    # ─── Active projects ─────────────────────────────────────────

    for idx, proj in enumerate(projects):
        name = proj.get("name", "?")
        status = proj.get("status", "")
        phase = proj.get("phase") or ""
        pm_live = proj.get("pm_live", False)
        live_badge = "  ● LIVE" if pm_live else ""
        text = f"# {name}{live_badge}\n*{status}*"
        if phase and phase != status:
            text += f" · {phase}"
        node_id = nid()
        nodes.append({
            "id": node_id,
            "type": "file",
            "file": f"projects/{name}.md",
            "x": PROJECT_X,
            "y": GRID_Y + idx * ROW_PITCH,
            "width": NODE_W,
            "height": NODE_H,
            "color": status_color(status)
        })

    # ─── Edges from Lilo to each cluster's group ─────────────────

    edges.append({
        "id": nid(), "fromNode": lilo_id, "fromSide": "bottom",
        "toNode": pm_group_id, "toSide": "top", "label": "scaffolds"
    })
    edges.append({
        "id": nid(), "fromNode": lilo_id, "fromSide": "bottom",
        "toNode": orch_group_id, "toSide": "top", "label": "dispatches"
    })
    edges.append({
        "id": nid(), "fromNode": lilo_id, "fromSide": "bottom",
        "toNode": mcp_group_id, "toSide": "top", "label": "uses"
    })
    if project_group_id:
        edges.append({
            "id": nid(), "fromNode": lilo_id, "fromSide": "bottom",
            "toNode": project_group_id, "toSide": "top", "label": "tracks"
        })

    # ─── Signature MCP↔specialist edges (sparse, illustrative) ───

    def link_mcp(mcp_name, specialist_name, label):
        if mcp_name in mcp_ids and specialist_name in {**pm_agent_ids, **orch_agent_ids}:
            target = pm_agent_ids.get(specialist_name) or orch_agent_ids.get(specialist_name)
            edges.append({
                "id": nid(),
                "fromNode": mcp_ids[mcp_name],
                "fromSide": "left",
                "toNode": target,
                "toSide": "right",
                "label": label,
                "color": "3"
            })

    link_mcp("picarx", "stitch-operator", "drives")
    link_mcp("ios-simulator", "ios-sim-driver", "drives")
    link_mcp("playwright", "scraper", "drives")
    link_mcp("playwright", "frontend", "previews")

    return {"nodes": nodes, "edges": edges}


def main():
    canvas = build_canvas()
    vault_dir = Path("../vault")
    vault_dir.mkdir(parents=True, exist_ok=True)
    out = vault_dir / "architecture.canvas"
    out.write_text(json.dumps(canvas, indent=2))
    print(f"Generated {out}")
    print(f"  Nodes: {len(canvas['nodes'])}")
    print(f"  Edges: {len(canvas['edges'])}")


if __name__ == "__main__":
    main()
