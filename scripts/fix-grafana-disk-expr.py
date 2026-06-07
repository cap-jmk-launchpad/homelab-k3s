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
    1: (0, 1), 2: (4, 1), 3: (8, 1), 4: (12, 1), 106: (16, 1), 107: (20, 1),
    5: (0, 4), 6: (4, 4), 7: (8, 4),
}
# Physical storage row header at y=7; cluster disk stats sit under that row.
DISK_STAT_LAYOUT = {109: (0, 8), 110: (8, 8), 111: (16, 8)}
STAT_W, STAT_H = 4, 3
DISK_STAT_W = 8


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
            "All 5 nodes: engine HDD+USB+NVMe, desktop WSL, blackpearl NVMe SSD, "
            "deck/anch0r Pi SD cards. Sum of mounted ext4 block devices (deduped)."
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
        "gridPos": {"x": 0, "y": 11, "w": 24, "h": 6},
        "id": 114,
        "options": {
            "cellHeight": "sm",
            "footer": {
                "show": True,
                "reducer": ["sum"],
                "countRows": False,
                "fields": ["Disk total GB", "Disk used GB"],
            },
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
    disk_desc = {
        109: "Cluster-wide physical disk use. Each block device counted once per node.",
        110: "Cluster sum of used space on all nodes (engine, desktop, blackpearl, deck, anch0r).",
        111: (
            "Cluster sum of mounted capacity on all 5 nodes — includes blackpearl NVMe (~444G), "
            "deck Pi SD (~470G), anch0r Pi SD (~58G), plus engine and desktop."
        ),
    }
    for panel in dash["panels"]:
        pid = panel.get("id")
        if pid in STAT_LAYOUT:
            x, y = STAT_LAYOUT[pid]
            panel["gridPos"] = {"x": x, "y": y, "w": STAT_W, "h": STAT_H}
        elif pid in DISK_STAT_LAYOUT:
            x, y = DISK_STAT_LAYOUT[pid]
            panel["gridPos"] = {"x": x, "y": y, "w": DISK_STAT_W, "h": STAT_H}
        if pid in disk_desc:
            panel["description"] = disk_desc[pid]
        if pid == 108:
            panel["gridPos"] = {"x": 0, "y": 7, "w": 24, "h": 1}
        elif pid == 112:
            panel["gridPos"] = {"x": 0, "y": 17, "w": 24, "h": 8}
        elif pid == 113:
            panel["gridPos"] = {"x": 0, "y": 25, "w": 24, "h": 8}
        elif pid == 114:
            panel["gridPos"] = {"x": 0, "y": 11, "w": 24, "h": 6}
            panel["options"]["footer"] = {
                "show": True,
                "reducer": ["sum"],
                "countRows": False,
                "fields": ["Disk total GB", "Disk used GB"],
            }
            panel["description"] = storage_table_panel()["description"]
        elif pid == 101:
            panel["gridPos"] = {"x": 0, "y": 33, "w": 24, "h": 1}
        elif pid == 10:
            panel["gridPos"] = {"x": 0, "y": 34, "w": 24, "h": 8}
        elif pid == 102:
            panel["gridPos"] = {"x": 0, "y": 42, "w": 24, "h": 1}
        elif pid == 11:
            panel["gridPos"] = {"x": 0, "y": 43, "w": 24, "h": 8}
        elif pid == 103:
            panel["gridPos"] = {"x": 0, "y": 51, "w": 24, "h": 1}
        elif pid == 12:
            panel["gridPos"] = {"x": 0, "y": 52, "w": 12, "h": 8}
        elif pid == 13:
            panel["gridPos"] = {"x": 12, "y": 52, "w": 12, "h": 8}
        elif pid == 104:
            panel["gridPos"] = {"x": 0, "y": 60, "w": 24, "h": 1}
        elif pid in {14, 15, 16}:
            panel["gridPos"]["y"] = 61
        elif pid == 105:
            panel["gridPos"] = {"x": 0, "y": 69, "w": 24, "h": 1}
        elif pid == 20:
            panel["gridPos"] = {"x": 0, "y": 70, "w": 24, "h": 10}

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
