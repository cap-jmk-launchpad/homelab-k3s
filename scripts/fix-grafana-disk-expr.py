#!/usr/bin/env python3
"""Disk PromQL helpers + dashboard patches."""
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DASH = REPO / "k8s/monitoring/homelab-cluster-resources-dashboard.json"

FS = (
    'fstype=~"ext4|xfs|btrfs|ext2|vfat",'
    'mountpoint!~"/boot.*|/run/credentials.*|/var/lib/kubelet/.*|/mnt/wsl.*|/mnt/c|/mnt/e|/host|/var/lib/docker.*|/run/k3s.*"'
)
JOIN = (
    '* on(instance) group_left(node) label_replace(kube_node_info, '
    '"instance", "$1:9100", "internal_ip", "(.*)")'
)

SIZE_I = f"sum by (instance) (max by (instance, device) (node_filesystem_size_bytes{{{FS}}}))"
AVAIL_I = f"sum by (instance) (max by (instance, device) (node_filesystem_avail_bytes{{{FS}}}))"
USED_I = f"({SIZE_I} - {AVAIL_I})"
SIZE_C = f"sum(max by (instance, device) (node_filesystem_size_bytes{{{FS}}}))"
AVAIL_C = f"sum(max by (instance, device) (node_filesystem_avail_bytes{{{FS}}}))"
USED_C = f"({SIZE_C} - {AVAIL_C})"

EXPR = {
    "cluster_pct": f"100 * (1 - {AVAIL_C} / {SIZE_C})",
    "cluster_used": f"{USED_C} / 1024^3",
    "cluster_total": f"{SIZE_C} / 1024^3",
    "node_pct": f"(100 * (1 - ({AVAIL_I} / {SIZE_I}))) {JOIN}",
    "node_used": f"({USED_I} / 1024^3) {JOIN}",
    "node_total": f"({SIZE_I} / 1024^3) {JOIN}",
}

STAT_LAYOUT = {
    1: (0, 1), 2: (4, 1), 3: (8, 1), 4: (12, 1), 109: (16, 1), 110: (20, 1),
    111: (0, 4), 106: (4, 4), 107: (8, 4), 5: (12, 4), 6: (16, 4), 7: (20, 4),
}
STAT_W, STAT_H = 4, 3


def apply_disk_exprs(dash: dict) -> None:
    for panel in dash["panels"]:
        pid = panel.get("id")
        for target in panel.get("targets", []):
            if "node_filesystem_" not in target.get("expr", ""):
                continue
            ref = target.get("refId", "")
            if pid == 109:
                target["expr"] = EXPR["cluster_pct"]
            elif pid == 110:
                target["expr"] = EXPR["cluster_used"]
            elif pid == 111:
                target["expr"] = EXPR["cluster_total"]
            elif pid == 112:
                target["expr"] = EXPR["node_pct"]
            elif pid == 113:
                target["expr"] = EXPR["node_used"]
            elif ref == "diskpct":
                target["expr"] = EXPR["node_pct"]
            elif ref == "diskused":
                target["expr"] = EXPR["node_used"]
            elif ref == "disktotal":
                target["expr"] = EXPR["node_total"]
            elif pid == 114:
                pass  # handled in table targets


def storage_table_panel() -> dict:
    return {
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "description": (
            "Mounted block devices per node (deduped). "
            "Unmounted hardware (e.g. engine LUKS NVMe ~930G) is not included until mounted."
        ),
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "custom": {"align": "auto", "cellOptions": {"type": "auto"}},
                "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}]},
            },
            "overrides": [
                {
                    "matcher": {"id": "byName", "options": "Disk %"},
                    "properties": [
                        {"id": "unit", "value": "percent"},
                        {"id": "decimals", "value": 1},
                        {"id": "custom.cellOptions", "value": {"type": "color-background", "mode": "gradient"}},
                        {"id": "max", "value": 100},
                        {"id": "min", "value": 0},
                        {
                            "id": "thresholds",
                            "value": {
                                "mode": "absolute",
                                "steps": [
                                    {"color": "green", "value": None},
                                    {"color": "yellow", "value": 70},
                                    {"color": "red", "value": 90},
                                ],
                            },
                        },
                    ],
                },
                {
                    "matcher": {"id": "byName", "options": "Disk total GB"},
                    "properties": [{"id": "unit", "value": "decgbytes"}, {"id": "decimals", "value": 1}],
                },
                {
                    "matcher": {"id": "byName", "options": "Disk used GB"},
                    "properties": [{"id": "unit", "value": "decgbytes"}, {"id": "decimals", "value": 1}],
                },
            ],
        },
        "gridPos": {"x": 0, "y": 8, "w": 24, "h": 6},
        "id": 114,
        "options": {
            "cellHeight": "sm",
            "footer": {"show": False},
            "showHeader": True,
            "sortBy": [{"desc": True, "displayName": "Disk total GB"}],
        },
        "targets": [
            {"datasource": {"type": "prometheus", "uid": "prometheus"}, "expr": "kube_node_info", "format": "table", "instant": True, "refId": "nodes"},
            {"datasource": {"type": "prometheus", "uid": "prometheus"}, "expr": EXPR["node_total"], "format": "table", "instant": True, "refId": "total"},
            {"datasource": {"type": "prometheus", "uid": "prometheus"}, "expr": EXPR["node_used"], "format": "table", "instant": True, "refId": "used"},
            {"datasource": {"type": "prometheus", "uid": "prometheus"}, "expr": EXPR["node_pct"], "format": "table", "instant": True, "refId": "pct"},
        ],
        "title": "Storage by node",
        "transformations": [
            {"id": "seriesToColumns", "options": {"byField": "node"}},
            {
                "id": "organize",
                "options": {
                    "excludeByName": {
                        "Time": True, "Time 1": True, "Time 2": True, "Time 3": True,
                        "Value #nodes": True, "__name__": True, "container": True, "endpoint": True,
                        "instance": True, "internal_ip": True, "job": True, "kernel_version": True,
                        "kubelet_version": True, "kubeproxy_version": True, "namespace": True,
                        "os_image": True, "pod": True, "provider_id": True, "service": True,
                        "system_uuid": True, "container_runtime_version": True,
                    },
                    "indexByName": {"node": 0, "Value #total": 1, "Value #used": 2, "Value #pct": 3},
                    "renameByName": {
                        "node": "node",
                        "Value #pct": "Disk %",
                        "Value #total": "Disk total GB",
                        "Value #used": "Disk used GB",
                    },
                },
            },
        ],
        "type": "table",
    }


def patch_layout(dash: dict) -> None:
    for panel in dash["panels"]:
        pid = panel.get("id")
        if pid in STAT_LAYOUT:
            x, y = STAT_LAYOUT[pid]
            panel["gridPos"] = {"x": x, "y": y, "w": STAT_W, "h": STAT_H}
        if pid == 108:
            panel["gridPos"] = {"x": 0, "y": 7, "w": 24, "h": 1}
        elif pid in {112, 113}:
            panel["gridPos"]["y"] += 6
        elif pid == 112:
            panel["gridPos"] = {"x": 0, "y": 14, "w": 24, "h": 8}
        elif pid == 113:
            panel["gridPos"] = {"x": 0, "y": 22, "w": 24, "h": 8}
        elif pid == 101:
            panel["gridPos"] = {"x": 0, "y": 30, "w": 24, "h": 1}
        elif pid == 10:
            panel["gridPos"] = {"x": 0, "y": 31, "w": 24, "h": 8}
        elif pid == 102:
            panel["gridPos"] = {"x": 0, "y": 39, "w": 24, "h": 1}
        elif pid == 11:
            panel["gridPos"] = {"x": 0, "y": 40, "w": 24, "h": 8}
        elif pid == 103:
            panel["gridPos"] = {"x": 0, "y": 48, "w": 24, "h": 1}
        elif pid == 12:
            panel["gridPos"] = {"x": 0, "y": 49, "w": 12, "h": 8}
        elif pid == 13:
            panel["gridPos"] = {"x": 12, "y": 49, "w": 12, "h": 8}
        elif pid == 104:
            panel["gridPos"] = {"x": 0, "y": 57, "w": 24, "h": 1}
        elif pid in {14, 15, 16}:
            panel["gridPos"]["y"] = 58
        elif pid == 105:
            panel["gridPos"] = {"x": 0, "y": 66, "w": 24, "h": 1}
        elif pid == 20:
            panel["gridPos"] = {"x": 0, "y": 67, "w": 24, "h": 10}

    if not any(p.get("id") == 114 for p in dash["panels"]):
        idx = next(i for i, p in enumerate(dash["panels"]) if p.get("id") == 112)
        dash["panels"].insert(idx, storage_table_panel())


def main() -> None:
    dash = json.loads(DASH.read_text(encoding="utf-8"))
    apply_disk_exprs(dash)
    patch_layout(dash)
    dash["version"] = dash.get("version", 5) + 1
    DASH.write_text(json.dumps(dash, indent=2) + "\n", encoding="utf-8")
    print(f"Patched {DASH} v{dash['version']}")
    print("cluster_total:", EXPR["cluster_total"])


if __name__ == "__main__":
    main()
