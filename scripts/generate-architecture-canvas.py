#!/usr/bin/env python3
"""
Generate an Obsidian Canvas showing Lilo's runtime architecture.

Design principles (after iteration):
  - File-type nodes render predictably (title above the card, properties pill
    inside if the file has frontmatter). Use them everywhere a real file exists.
  - Text-type nodes with markdown headings (#, ##) render unreliably in small
    boxes — the heading consumes the visible area and body content gets
    clipped. Keep text-node content to one short bold line.
  - Group nodes render their `label` above the rectangle (top-left). Pad the
    cluster band so the label has room above.
  - Lilo is a wide banner above all clusters, not crammed between them.

Reads:
  - templates/team/.claude/agent-registry/*.md  (PM specialists; excludes
    README, test placeholder, and stitch-operator which lives in the
    orchestrator-only cluster)
  - .claude/agents/  (via the vault's orchestrator-agents symlink)
  - .mcp.json
  - pipeline.json  (optional, for the live-projects cluster)

Outputs:
  ../vault/architecture.canvas (JSON)
"""

import json
from pathlib import Path


# ─── Visual constants ─────────────────────────────────────────────────

NODE_W = 240
NODE_H = 88
ROW_PITCH = 130
GROUP_PAD_TOP = 50      # room for the group label above the rectangle
GROUP_PAD_OTHER = 40
COL_PITCH = 260         # NODE_W + 20 gap

LILO_W = 1240
LILO_H = 120
LILO_Y = -260           # banner sits above everything

# Cluster lanes (left to right, disjoint, leaving COL_PITCH between cells)
PM_X      = [-1240, -980, -720]
ORCH_X    = -420
MCP_X     = -140
PROJECT_X = [180, 440]              # projects in two columns
GRID_Y    = 80                       # first row of nodes inside each group
GROUP_Y   = GRID_Y - GROUP_PAD_TOP   # = 30


# ─── Source readers ───────────────────────────────────────────────────

def scan_registry():
    """PM specialists from the team template registry.

    Excludes README, the placeholder `test`, and `stitch-operator`
    (lives in the orchestrator-only cluster).
    """
    excluded = {"README.md", "test.md", "stitch-operator.md"}
    registry = Path("templates/team/.claude/agent-registry")
    if not registry.exists():
        return []
    return [md.stem for md in sorted(registry.glob("*.md"))
            if md.name not in excluded]


def get_orch_agents():
    """Orchestrator-only subagents — exactly the three that don't live in
    the PM registry. Linked via vault/orchestrator-agents → .claude/agents/.
    """
    orch_dir = Path(".claude/agents")
    targets = ["outbox-sweeper", "pipeline-syncer", "stitch-operator"]
    return [t for t in targets if (orch_dir / f"{t}.md").exists()]


def get_mcps():
    """List of (name, short_description) for project + summary MCPs."""
    try:
        servers = json.loads(Path(".mcp.json").read_text()).get("mcpServers", {})
    except Exception:
        servers = {}
    out = []
    for name, blurb in [
        ("lilo-tools",     "MCP bridge → tools/ registry"),
        ("playwright",     "headless browser"),
        ("ios-simulator",  "Xcode iOS Simulator"),
        ("picarx",         "the Stitch robot (SSE)"),
    ]:
        if name in servers:
            out.append((name, blurb))
    out.append(("account-level MCPs",
                "Notion · Figma · Gmail\nCalendar · GitHub · ClickUp"))
    return out


def get_projects():
    """Read pipeline.json's projects list. Empty if file missing."""
    p = Path("pipeline.json")
    if not p.exists():
        return []
    try:
        return json.loads(p.read_text()).get("projects", [])
    except Exception:
        return []


# ─── Canvas builder ───────────────────────────────────────────────────

def status_color(status):
    s = (status or "").lower()
    if s == "blocked":                                        return "1"  # red
    if s == "paused":                                         return "3"  # yellow
    if s in ("done", "complete", "completed", "closed"):     return "6"  # purple
    if s in ("active", "in_progress"):                       return "4"  # green
    return "5"                                                            # cyan (solo/other)


def build_canvas():
    nodes = []
    edges = []
    counter = [0]

    def nid():
        counter[0] += 1
        return f"n{counter[0]}"

    pm_agents = scan_registry()
    orch_agents = get_orch_agents()
    mcps = get_mcps()
    projects = get_projects()

    # ─── Group rectangles (drawn first → behind their children) ─

    pm_rows = (len(pm_agents) + 2) // 3
    pm_grid_h = pm_rows * ROW_PITCH
    pm_grid_w = 3 * COL_PITCH - (COL_PITCH - NODE_W)  # 3 cells with the last cell's gap excluded

    pm_group_id = nid()
    nodes.append({
        "id": pm_group_id, "type": "group",
        "label": "PM Template — Specialists",
        "x": PM_X[0] - GROUP_PAD_OTHER,
        "y": GROUP_Y,
        "width": pm_grid_w + 2 * GROUP_PAD_OTHER,
        "height": pm_grid_h + GROUP_PAD_TOP + GROUP_PAD_OTHER,
        "color": "4"
    })

    orch_group_id = nid()
    orch_rows = max(len(orch_agents), 1)
    nodes.append({
        "id": orch_group_id, "type": "group",
        "label": "Lilo's Subagents",
        "x": ORCH_X - GROUP_PAD_OTHER,
        "y": GROUP_Y,
        "width": NODE_W + 2 * GROUP_PAD_OTHER,
        "height": orch_rows * ROW_PITCH + GROUP_PAD_TOP + GROUP_PAD_OTHER,
        "color": "2"
    })

    mcp_group_id = nid()
    mcp_rows = max(len(mcps), 1)
    nodes.append({
        "id": mcp_group_id, "type": "group",
        "label": "MCPs & Connectors",
        "x": MCP_X - GROUP_PAD_OTHER,
        "y": GROUP_Y,
        "width": NODE_W + 2 * GROUP_PAD_OTHER,
        "height": mcp_rows * ROW_PITCH + GROUP_PAD_TOP + GROUP_PAD_OTHER,
        "color": "3"
    })

    project_group_id = None
    if projects:
        project_group_id = nid()
        proj_rows = (len(projects) + 1) // 2  # 2 columns
        proj_grid_w = 2 * COL_PITCH - (COL_PITCH - NODE_W)
        nodes.append({
            "id": project_group_id, "type": "group",
            "label": "Active Projects (live state)",
            "x": PROJECT_X[0] - GROUP_PAD_OTHER,
            "y": GROUP_Y,
            "width": proj_grid_w + 2 * GROUP_PAD_OTHER,
            "height": proj_rows * ROW_PITCH + GROUP_PAD_TOP + GROUP_PAD_OTHER,
            "color": "6"
        })

    # ─── Lilo banner — wide, plain text (no markdown headings) ───

    lilo_id = "lilo"
    # Center the banner across the full cluster span
    leftmost = PM_X[0] - GROUP_PAD_OTHER
    rightmost = ((PROJECT_X[-1] if projects else MCP_X) + NODE_W + GROUP_PAD_OTHER)
    lilo_x = (leftmost + rightmost) // 2 - LILO_W // 2
    nodes.append({
        "id": lilo_id, "type": "text",
        "text": (
            "**Lilo** — the orchestrator\n\n"
            "Talks to the operator on Telegram + terminal · "
            "Scaffolds PMs in tmux · Dispatches subagents · "
            "Syncs Notion + vault"
        ),
        "x": lilo_x, "y": LILO_Y,
        "width": LILO_W, "height": LILO_H,
        "color": "5"
    })

    # ─── PM cluster (file-type, 3 columns) ───────────────────────

    pm_ids = {}
    for idx, name in enumerate(pm_agents):
        col = idx % 3
        row = idx // 3
        node_id = nid()
        pm_ids[name] = node_id
        nodes.append({
            "id": node_id, "type": "file",
            "file": f"agents/{name}.md",
            "x": PM_X[col],
            "y": GRID_Y + row * ROW_PITCH,
            "width": NODE_W, "height": NODE_H,
            "color": "4"
        })

    # ─── Orch cluster (file-type via the new symlink) ────────────

    orch_ids = {}
    for idx, name in enumerate(orch_agents):
        node_id = nid()
        orch_ids[name] = node_id
        nodes.append({
            "id": node_id, "type": "file",
            "file": f"orchestrator-agents/{name}.md",
            "x": ORCH_X,
            "y": GRID_Y + idx * ROW_PITCH,
            "width": NODE_W, "height": NODE_H,
            "color": "2"
        })

    # ─── MCP cluster (text-type, plain text only) ────────────────

    mcp_ids = {}
    for idx, (name, blurb) in enumerate(mcps):
        text = f"**{name}**"
        if blurb:
            text += f"\n{blurb}"
        node_id = nid()
        mcp_ids[name] = node_id
        nodes.append({
            "id": node_id, "type": "text",
            "text": text,
            "x": MCP_X,
            "y": GRID_Y + idx * ROW_PITCH,
            "width": NODE_W,
            "height": NODE_H + (16 if "\n" in text else 0),
            "color": "3"
        })

    # ─── Project cluster (file-type, 2 columns, color by status) ─

    for idx, proj in enumerate(projects):
        name = proj.get("name", "?")
        col = idx % 2
        row = idx // 2
        node_id = nid()
        nodes.append({
            "id": node_id, "type": "file",
            "file": f"projects/{name}.md",
            "x": PROJECT_X[col],
            "y": GRID_Y + row * ROW_PITCH,
            "width": NODE_W, "height": NODE_H,
            "color": status_color(proj.get("status"))
        })

    # ─── Edges: Lilo banner → each cluster group ────────────────

    edges.append({"id": nid(), "fromNode": lilo_id, "fromSide": "bottom",
                  "toNode": pm_group_id, "toSide": "top", "label": "scaffolds"})
    edges.append({"id": nid(), "fromNode": lilo_id, "fromSide": "bottom",
                  "toNode": orch_group_id, "toSide": "top", "label": "dispatches"})
    edges.append({"id": nid(), "fromNode": lilo_id, "fromSide": "bottom",
                  "toNode": mcp_group_id, "toSide": "top", "label": "uses"})
    if project_group_id:
        edges.append({"id": nid(), "fromNode": lilo_id, "fromSide": "bottom",
                      "toNode": project_group_id, "toSide": "top", "label": "tracks"})

    return {"nodes": nodes, "edges": edges}


def main():
    canvas = build_canvas()
    vault = Path("../vault")
    vault.mkdir(parents=True, exist_ok=True)
    out = vault / "architecture.canvas"
    out.write_text(json.dumps(canvas, indent=2))
    print(f"Generated {out}")
    print(f"  Nodes: {len(canvas['nodes'])}  Edges: {len(canvas['edges'])}")


if __name__ == "__main__":
    main()
