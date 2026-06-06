#!/usr/bin/env python3
"""Add physical storage panels to homelab-cluster-resources Grafana dashboard."""
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
path = REPO / "k8s/monitoring/homelab-cluster-resources-dashboard.json"

with path.open() as f:
    dash = json.load(f)

FS = '{fstype=~"ext4|xfs|vfat|ext2|btrfs",mountpoint!~"/boot.*|/run/credentials.*"}'
JOIN = (
    '* on(instance) group_left(node) label_replace(kube_node_info, '
    '"instance", "$1:9100", "internal_ip", "(.*)")'
)


def panel_stat(panel_id, x, y, w, title, expr, unit="decgbytes", decimals=1, desc=None):
    panel = {
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "palette-classic"},
                "decimals": decimals,
                "unit": unit,
            },
            "overrides": [],
        },
        "gridPos": {"x": x, "y": y, "w": w, "h": 5},
        "id": panel_id,
        "options": {
            "colorMode": "value",
            "graphMode": "none",
            "justifyMode": "auto",
            "orientation": "auto",
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "textMode": "auto",
        },
        "targets": [
            {
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "expr": expr,
                "legendFormat": "",
                "refId": "A",
            }
        ],
        "title": title,
        "type": "stat",
    }
    if desc:
        panel["description"] = desc
    return panel


def panel_gauge(panel_id, x, y, w, title, expr, desc=None):
    panel = {
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "max": 100,
                "min": 0,
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "green", "value": None},
                        {"color": "yellow", "value": 70},
                        {"color": "red", "value": 90},
                    ],
                },
                "unit": "percent",
            },
            "overrides": [],
        },
        "gridPos": {"x": x, "y": y, "w": w, "h": 5},
        "id": panel_id,
        "options": {
            "colorMode": "value",
            "graphMode": "area",
            "justifyMode": "auto",
            "orientation": "auto",
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
            "textMode": "auto",
        },
        "targets": [
            {
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "expr": expr,
                "legendFormat": "disk %",
                "refId": "A",
            }
        ],
        "title": title,
        "type": "gauge",
    }
    if desc:
        panel["description"] = desc
    return panel


for panel in dash["panels"]:
    if panel["gridPos"]["y"] >= 11:
        panel["gridPos"]["y"] += 14

insert_at = next(i for i, panel in enumerate(dash["panels"]) if panel.get("id") == 101)
new_panels = [
    {
        "collapsed": False,
        "gridPos": {"x": 0, "y": 11, "w": 24, "h": 1},
        "id": 108,
        "title": "Physical storage",
        "type": "row",
    },
    panel_gauge(
        109,
        0,
        12,
        4,
        "Disk used %",
        f"100 * (1 - sum(node_filesystem_avail_bytes{FS}) / sum(node_filesystem_size_bytes{FS}))",
        "Sum of ext4/xfs/vfat/btrfs filesystems on all scraped nodes.",
    ),
    panel_stat(
        110,
        4,
        12,
        4,
        "Disk used GB",
        f"(sum(node_filesystem_size_bytes{FS}) - sum(node_filesystem_avail_bytes{FS})) / 1024^3",
    ),
    panel_stat(
        111,
        8,
        12,
        4,
        "Disk total GB",
        f"sum(node_filesystem_size_bytes{FS}) / 1024^3",
        desc="Includes engine external USB when mounted (e.g. /media/.../INTENSO).",
    ),
    {
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "palette-classic"},
                "custom": {
                    "axisBorderShow": False,
                    "drawStyle": "line",
                    "fillOpacity": 15,
                    "lineWidth": 1,
                    "showPoints": "never",
                    "spanNulls": False,
                },
                "max": 100,
                "min": 0,
                "unit": "percent",
            },
            "overrides": [],
        },
        "gridPos": {"x": 0, "y": 17, "w": 24, "h": 8},
        "id": 112,
        "options": {
            "legend": {
                "calcs": ["lastNotNull", "max"],
                "displayMode": "table",
                "placement": "bottom",
                "showLegend": True,
            },
            "tooltip": {"mode": "multi", "sort": "desc"},
        },
        "targets": [
            {
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "refId": "A",
                "expr": (
                    f"(100 * (1 - sum by (instance) (node_filesystem_avail_bytes{FS}) / "
                    f"sum by (instance) (node_filesystem_size_bytes{FS}))) {JOIN}"
                ),
                "legendFormat": "{{node}}",
            }
        ],
        "title": "Disk used % by node",
        "type": "timeseries",
        "description": "Per-node sum of physical filesystems.",
    },
    {
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "palette-classic"},
                "custom": {
                    "axisBorderShow": False,
                    "drawStyle": "line",
                    "fillOpacity": 10,
                    "lineWidth": 1,
                    "showPoints": "never",
                },
                "unit": "decgbytes",
            },
            "overrides": [],
        },
        "gridPos": {"x": 0, "y": 25, "w": 24, "h": 8},
        "id": 113,
        "options": {
            "legend": {
                "calcs": ["lastNotNull"],
                "displayMode": "table",
                "placement": "bottom",
                "showLegend": True,
            },
            "tooltip": {"mode": "multi", "sort": "desc"},
        },
        "targets": [
            {
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "refId": "A",
                "expr": (
                    f"((sum by (instance) (node_filesystem_size_bytes{FS}) - "
                    f"sum by (instance) (node_filesystem_avail_bytes{FS})) / 1024^3) {JOIN}"
                ),
                "legendFormat": "{{node}} used",
            }
        ],
        "title": "Disk used GB by node",
        "type": "timeseries",
    },
]
dash["panels"][insert_at:insert_at] = new_panels

for panel in dash["panels"]:
    if panel.get("id") != 20:
        continue
    panel["targets"].extend(
        [
            {
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "expr": (
                    f"(100 * (1 - sum by (instance) (node_filesystem_avail_bytes{FS}) / "
                    f"sum by (instance) (node_filesystem_size_bytes{FS}))) {JOIN}"
                ),
                "format": "table",
                "instant": True,
                "legendFormat": "",
                "refId": "diskpct",
            },
            {
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "expr": (
                    f"((sum by (instance) (node_filesystem_size_bytes{FS}) - "
                    f"sum by (instance) (node_filesystem_avail_bytes{FS})) / 1024^3) {JOIN}"
                ),
                "format": "table",
                "instant": True,
                "legendFormat": "",
                "refId": "diskused",
            },
            {
                "datasource": {"type": "prometheus", "uid": "prometheus"},
                "expr": f"(sum by (instance) (node_filesystem_size_bytes{FS}) / 1024^3) {JOIN}",
                "format": "table",
                "instant": True,
                "legendFormat": "",
                "refId": "disktotal",
            },
        ]
    )
    org = panel["transformations"][1]["options"]
    org["indexByName"]["Value #diskpct"] = 9
    org["indexByName"]["Value #diskused"] = 10
    org["indexByName"]["Value #disktotal"] = 11
    org["renameByName"]["Value #diskpct"] = "Disk %"
    org["renameByName"]["Value #diskused"] = "Disk used GB"
    org["renameByName"]["Value #disktotal"] = "Disk total GB"
    org["excludeByName"]["Time 9"] = True
    org["excludeByName"]["Time 10"] = True
    org["excludeByName"]["Time 11"] = True
    panel["fieldConfig"]["overrides"].extend(
        [
            {
                "matcher": {"id": "byName", "options": "Disk %"},
                "properties": [
                    {"id": "unit", "value": "percent"},
                    {"id": "decimals", "value": 1},
                    {
                        "id": "custom.cellOptions",
                        "value": {"type": "color-background", "mode": "gradient"},
                    },
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
                "matcher": {"id": "byName", "options": "Disk used GB"},
                "properties": [
                    {"id": "unit", "value": "decgbytes"},
                    {"id": "decimals", "value": 1},
                ],
            },
            {
                "matcher": {"id": "byName", "options": "Disk total GB"},
                "properties": [
                    {"id": "unit", "value": "decgbytes"},
                    {"id": "decimals", "value": 1},
                ],
            },
        ]
    )

if "storage" not in dash["tags"]:
    dash["tags"].append("storage")
dash["version"] = 2

with path.open("w", newline="\n") as f:
    json.dump(dash, f, indent=2)
    f.write("\n")

print(f"Updated {path}")
