#!/usr/bin/env python3
"""
Generate Obsidian Canvas file showing Lilo orchestrator architecture.

Reads:
  - templates/team/.claude/agent-registry/*.md (all specialist agents)
  - .mcp.json (wired MCP servers)
  - .claude/agents/ (orchestrator-only subagents)

Outputs:
  ../vault/architecture.canvas (JSON, vault-rooted file paths)

Layout: Lilo at top, three category branches (PM template, Lilo subagents, MCPs)
with grid-laid agent nodes, category labels, and labeled edges.
"""

import json
import os
import re
from pathlib import Path

def get_agent_name_and_description(filepath):
    """Extract agent name (from filename) and first-line description from file."""
    name = Path(filepath).stem
    try:
        with open(filepath, 'r') as f:
            content = f.read()
            # Look for # Heading or just take first non-empty line as description
            match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
            if match:
                desc = match.group(1).strip()
                return name, desc
    except Exception:
        pass
    return name, ""

def scan_registry():
    """Scan agent registry and return list of (name, description) tuples."""
    registry_dir = Path("templates/team/.claude/agent-registry")
    agents = []
    # Exclude non-agent files
    exclude = {"README.md", "code.md", "docs.md", "frontend.md", "test.md"}
    if registry_dir.exists():
        for md_file in sorted(registry_dir.glob("*.md")):
            if md_file.name in exclude:
                continue
            name, desc = get_agent_name_and_description(md_file)
            agents.append((name, desc))
    return agents

def get_orchestrator_only_agents():
    """List orchestrator-only agents from .claude/agents/."""
    agents_dir = Path(".claude/agents")
    orchestrator_only = []
    targets = ["outbox-sweeper", "pipeline-syncer", "stitch-operator"]
    for target in targets:
        file_path = agents_dir / f"{target}.md"
        if file_path.exists():
            name, desc = get_agent_name_and_description(file_path)
            orchestrator_only.append((name, desc))
    return orchestrator_only

def get_mcps():
    """Extract MCP servers from .mcp.json."""
    mcps = []
    try:
        with open(".mcp.json", 'r') as f:
            config = json.load(f)
            mcp_servers = config.get("mcpServers", {})
            for mcp_name in ["lilo-tools", "playwright", "ios-simulator", "picarx"]:
                if mcp_name in mcp_servers:
                    mcps.append((mcp_name, ""))
            # Add account-level summary
            mcps.append(("account-level MCPs", "Notion, Figma, Gmail, Calendar, GitHub, HubSpot, etc."))
    except Exception:
        pass
    return mcps

def build_canvas():
    """Build the full canvas JSON structure."""
    nodes = []
    edges = []
    node_id_counter = [0]

    def next_id():
        node_id_counter[0] += 1
        return f"n{node_id_counter[0]}"

    # 1. Lilo node at top-center
    lilo_id = "lilo"
    nodes.append({
        "id": lilo_id,
        "type": "text",
        "text": "# Lilo\norchestrator",
        "x": 0,
        "y": 0,
        "width": 300,
        "height": 120,
        "color": "5"  # cyan
    })

    # Layout constants. Obsidian renders the file-node's title in grey
    # ABOVE the card, which eats ~30px. Row pitch must comfortably exceed
    # node height to keep titles from overlapping the row above.
    NODE_W = 260
    NODE_H = 90
    ROW_PITCH = 170
    COL_PITCH = 300
    GRID_Y_START = 360

    # Three non-overlapping x-lanes for the three clusters:
    #   PM cluster: 3 cols wide   → x ∈ [-1000, -180]   (end = -180 + NODE_W = 80)
    #   Orch cluster: 1 col wide  → x ∈ [180]
    #   MCP cluster: 1 col wide   → x ∈ [560]
    PM_X = [-1000, -700, -400]
    ORCH_X = 180
    MCP_X = 560

    # 2. Category labels at y=200
    pm_label_id = next_id()
    nodes.append({
        "id": pm_label_id,
        "type": "text",
        "text": "## PM Template\nSpecialists",
        "x": -700,
        "y": 200,
        "width": 240,
        "height": 80,
        "color": "4"  # green
    })

    subagent_label_id = next_id()
    nodes.append({
        "id": subagent_label_id,
        "type": "text",
        "text": "## Lilo's\nSubagents",
        "x": ORCH_X,
        "y": 200,
        "width": 240,
        "height": 80,
        "color": "2"  # orange
    })

    mcp_label_id = next_id()
    nodes.append({
        "id": mcp_label_id,
        "type": "text",
        "text": "## MCPs\n& Connectors",
        "x": MCP_X,
        "y": 200,
        "width": 240,
        "height": 80,
        "color": "3"  # yellow
    })

    # 3. Edges from Lilo to category labels
    edges.append({
        "id": next_id(),
        "fromNode": lilo_id,
        "fromSide": "bottom",
        "toNode": pm_label_id,
        "toSide": "top",
        "label": "scaffolds"
    })

    edges.append({
        "id": next_id(),
        "fromNode": lilo_id,
        "fromSide": "bottom",
        "toNode": subagent_label_id,
        "toSide": "top",
        "label": "dispatches"
    })

    edges.append({
        "id": next_id(),
        "fromNode": lilo_id,
        "fromSide": "bottom",
        "toNode": mcp_label_id,
        "toSide": "top",
        "label": "uses"
    })

    # 4. PM template specialists (grid layout, 3 cols)
    registry_agents = scan_registry()
    for idx, (name, desc) in enumerate(registry_agents):
        col = idx % 3
        row = idx // 3
        node_id = next_id()
        nodes.append({
            "id": node_id,
            "type": "file",
            "file": f"agents/{name}.md",
            "x": PM_X[col],
            "y": GRID_Y_START + (row * ROW_PITCH),
            "width": NODE_W,
            "height": NODE_H,
            "color": "4"  # green
        })

    # 5. Orchestrator-only subagents (single column, no overlap with PM grid)
    orch_agents = get_orchestrator_only_agents()
    for idx, (name, desc) in enumerate(orch_agents):
        node_id = next_id()
        nodes.append({
            "id": node_id,
            "type": "text",
            "text": f"# {name}\norchestrator-only\n(see .claude/agents/)",
            "x": ORCH_X,
            "y": GRID_Y_START + (idx * ROW_PITCH),
            "width": NODE_W,
            "height": NODE_H + 20,  # slightly taller for the 3-line text
            "color": "2"  # orange
        })

    # 6. MCPs (single column, separate lane)
    mcps = get_mcps()
    for idx, (name, desc) in enumerate(mcps):
        text_content = f"# {name}"
        if desc:
            text_content += f"\n{desc}"
        node_id = next_id()
        nodes.append({
            "id": node_id,
            "type": "text",
            "text": text_content,
            "x": MCP_X,
            "y": GRID_Y_START + (idx * ROW_PITCH),
            "width": NODE_W,
            "height": NODE_H,
            "color": "3"  # yellow
        })

    return {"nodes": nodes, "edges": edges}

def main():
    """Generate and write the canvas file."""
    canvas = build_canvas()

    # Ensure vault directory exists
    vault_dir = Path("../vault")
    vault_dir.mkdir(parents=True, exist_ok=True)

    # Write canvas file
    canvas_path = vault_dir / "architecture.canvas"
    with open(canvas_path, 'w') as f:
        json.dump(canvas, f, indent=2)

    print(f"Generated {canvas_path}")
    print(f"  Nodes: {len(canvas['nodes'])}")
    print(f"  Edges: {len(canvas['edges'])}")

if __name__ == "__main__":
    main()
