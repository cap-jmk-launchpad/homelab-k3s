#!/usr/bin/env python3
"""Assign fixed per-node colors across homelab Grafana dashboards."""
from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]

# Consistent palette — same node = same color in every panel/dashboard.
NODE_COLORS: dict[str, str] = {
    "blackpearl": "#5794F2",  # blue — control plane / edge
    "engine": "#73BF69",  # green — primary worker + GPU
    "desktop": "#FF9830",  # orange — WSL burst
    "deck": "#B877D9",  # purple — Pi worker
    "anch0r": "#FADE2A",  # yellow — Pi edge
}

NODE_REGEX_PREFIXES = tuple(f"/^{re.escape(node)}" for node in NODE_COLORS)


def series_color_override(node: str, color: str) -> dict[str, Any]:
    return {
        "matcher": {
            "id": "byRegexp",
            "options": f"/^{re.escape(node)}(\\s|$)/",
        },
        "properties": [
            {
                "id": "color",
                "value": {"fixedColor": color, "mode": "fixed"},
            }
        ],
    }


def node_series_overrides() -> list[dict[str, Any]]:
    return [series_color_override(n, c) for n, c in NODE_COLORS.items()]


def node_column_override() -> dict[str, Any]:
    return {
        "matcher": {"id": "byName", "options": "node"},
        "properties": [
            {
                "id": "mappings",
                "value": [
                    {
                        "type": "value",
                        "options": {
                            node: {
                                "color": color,
                                "index": idx,
                                "text": node,
                            }
                            for idx, (node, color) in enumerate(NODE_COLORS.items())
                        },
                    }
                ],
            },
            {
                "id": "custom.cellOptions",
                "value": {"type": "color-text"},
            },
        ],
    }


def is_node_color_override(override: dict[str, Any]) -> bool:
    matcher = override.get("matcher", {})
    if matcher.get("id") != "byRegexp":
        return False
    opt = matcher.get("options", "")
    return any(opt.startswith(prefix) for prefix in NODE_REGEX_PREFIXES)


def is_node_column_override(override: dict[str, Any]) -> bool:
    matcher = override.get("matcher", {})
    if matcher.get("id") != "byName" or matcher.get("options") != "node":
        return False
    return any(prop.get("id") == "mappings" for prop in override.get("properties", []))


def panel_uses_node_series(panel: dict[str, Any]) -> bool:
    """Any timeseries — node regex overrides only match series named after nodes."""
    return panel.get("type") == "timeseries"


def panel_has_node_column(panel: dict[str, Any]) -> bool:
    if panel.get("type") != "table":
        return False
    for tr in panel.get("transformations", []):
        if tr.get("id") != "organize":
            continue
        opts = tr.get("options", {})
        renames = opts.get("renameByName", {})
        if "node" in renames or "node" in renames.values():
            return True
    for sort in panel.get("options", {}).get("sortBy", []):
        if sort.get("displayName") == "node":
            return True
    return False


def merge_overrides(
    existing: list[dict[str, Any]],
    additions: list[dict[str, Any]],
    *,
    drop_node_color: bool = False,
    drop_node_column: bool = False,
) -> list[dict[str, Any]]:
    kept: list[dict[str, Any]] = []
    for ov in existing:
        if drop_node_color and is_node_color_override(ov):
            continue
        if drop_node_column and is_node_column_override(ov):
            continue
        kept.append(ov)
    return kept + additions


def patch_panel(panel: dict[str, Any]) -> bool:
    changed = False
    fc = panel.setdefault("fieldConfig", {})
    overrides = fc.setdefault("overrides", [])

    if panel_uses_node_series(panel):
        fc["overrides"] = merge_overrides(
            overrides, node_series_overrides(), drop_node_color=True
        )
        changed = True

    if panel_has_node_column(panel):
        fc["overrides"] = merge_overrides(
            fc["overrides"],
            [node_column_override()],
            drop_node_column=True,
        )
        changed = True

    return changed


def patch_gpu_dashboard(dash: dict[str, Any]) -> int:
    """Prefix engine/desktop legends and apply node colors."""
    count = 0
    for panel in dash.get("panels", []):
        title = panel.get("title", "")
        if title.startswith("Engine"):
            for target in panel.get("targets", []):
                lf = target.get("legendFormat", "")
                if lf and not lf.startswith("engine "):
                    target["legendFormat"] = f"engine {lf}"
                    count += 1
        elif title.startswith("Desktop"):
            for target in panel.get("targets", []):
                lf = target.get("legendFormat", "")
                if lf and not lf.startswith("desktop "):
                    target["legendFormat"] = f"desktop {lf}"
                    count += 1
        if patch_panel(panel):
            count += 1
    return count


def patch_dashboard(path: Path) -> None:
    dash = json.loads(path.read_text(encoding="utf-8"))
    changed = 0
    for panel in dash.get("panels", []):
        if patch_panel(panel):
            changed += 1

    if path.name == "homelab-gpu-dashboard.json":
        changed += patch_gpu_dashboard(dash)

    dash["version"] = dash.get("version", 1) + 1
    path.write_text(json.dumps(dash, indent=2) + "\n", encoding="utf-8")
    print(f"Patched {path.name}: {changed} panel(s), version {dash['version']}")


def main() -> None:
    mon = REPO / "k8s/monitoring"
    for name in ("homelab-cluster-resources-dashboard.json", "homelab-gpu-dashboard.json"):
        patch_dashboard(mon / name)


if __name__ == "__main__":
    main()
