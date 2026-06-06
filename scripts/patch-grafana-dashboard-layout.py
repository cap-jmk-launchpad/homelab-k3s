#!/usr/bin/env python3
"""Fix disk PromQL (device dedupe) and reorganize cluster stat tiles."""
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DASH = REPO / "k8s/monitoring/homelab-cluster-resources-dashboard.json"

FS = (
    'fstype=~"ext4|xfs|btrfs|ext2|vfat",'
    'mountpoint!~"/boot.*|/run/credentials.*|/var/lib/kubelet/.*|/mnt/wsl.*|^/mnt/c$|^/mnt/e$|^/host$"'
)
JOIN = (
    '* on(instance) group_left(node) label_replace(kube_node_info, '
    '"instance", "$1:9100", "internal_ip", "(.*)")'
)

SIZE_BY_INSTANCE = f"sum by (instance) (max by (instance, device) (node_filesystem_size_bytes{{{FS}}}))"
AVAIL_BY_INSTANCE = f"sum by (instance) (max by (instance, device) (node_filesystem_avail_bytes{{{FS}}}))"
USED_BY_INSTANCE = f"({SIZE_BY_INSTANCE} - {AVAIL_BY_INSTANCE})"

SIZE_CLUSTER = f"sum(max by (instance, device) (node_filesystem_size_bytes{{{FS}}}))"
AVAIL_CLUSTER = f"sum(max by (instance, device) (node_filesystem_avail_bytes{{{FS}}}))"
USED_CLUSTER = f"({SIZE_CLUSTER} - {AVAIL_CLUSTER})"

DISK_PCT_CLUSTER = f"100 * (1 - {AVAIL_CLUSTER} / {SIZE_CLUSTER})"
DISK_USED_CLUSTER = f"{USED_CLUSTER} / 1024^3"
DISK_TOTAL_CLUSTER = f"{SIZE_CLUSTER} / 1024^3"

DISK_PCT_NODE = f"(100 * (1 - ({AVAIL_BY_INSTANCE} / {SIZE_BY_INSTANCE}))) {JOIN}"
DISK_USED_NODE = f"({USED_BY_INSTANCE} / 1024^3) {JOIN}"
DISK_TOTAL_NODE = f"({SIZE_BY_INSTANCE} / 1024^3) {JOIN}"

OLD_FS_PATTERN = re.compile(
    r'node_filesystem_(?:size|avail)_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}'
)

STAT_GAUGE_IDS = {1, 4, 106, 109}
STAT_LAYOUT = {
    1: (0, 1),
    2: (4, 1),
    3: (8, 1),
    4: (12, 1),
    109: (16, 1),
    110: (20, 1),
    111: (0, 4),
    106: (4, 4),
    107: (8, 4),
    5: (12, 4),
    6: (16, 4),
    7: (20, 4),
}
STAT_W, STAT_H = 4, 3

EXPR_BY_ID = {
    109: DISK_PCT_CLUSTER,
    110: DISK_USED_CLUSTER,
    111: DISK_TOTAL_CLUSTER,
}

GRAPH_ROWS = [
    (108, "Physical storage", 7),
    (112, None, 8),
    (113, None, 16),
    (101, "Per-node memory", 24),
    (10, None, 25),
    (102, "Per-node CPU", 33),
    (11, None, 34),
    (103, "Network per node", 42),
    (12, None, 43),
    (13, None, 43),
    (104, "GPU per node (DCGM)", 51),
    (None, None, 52),  # gpu panels 14,15,16 handled below
    (105, "Current snapshot (all nodes)", 60),
    (20, None, 61),
]

GPU_PANELS = {14: 0, 15: 8, 16: 16}


def replace_disk_exprs(text: str) -> str:
    """Replace legacy naive sum() disk queries with device-deduped ones."""
    replacements = [
        (
            r'100 \* \(1 - sum\(sum by \(instance\) \(max by \(instance, device\) \(node_filesystem_avail_bytes\{[^}]+\}\)\)\) / sum\(sum by \(instance\) \(max by \(instance, device\) \(node_filesystem_size_bytes\{[^}]+\}\)\)\)\)',
            DISK_PCT_CLUSTER,
        ),
        (
            r'sum\(\(sum by \(instance\) \(max by \(instance, device\) \(node_filesystem_size_bytes\{[^}]+\}\)\) - sum by \(instance\) \(max by \(instance, device\) \(node_filesystem_avail_bytes\{[^}]+\}\)\)\)\) / 1024\^3',
            DISK_USED_CLUSTER,
        ),
        (
            r'sum\(sum by \(instance\) \(max by \(instance, device\) \(node_filesystem_size_bytes\{[^}]+\}\)\)\) / 1024\^3',
            DISK_TOTAL_CLUSTER,
        ),
        (
            r'100 \* \(1 - sum\(node_filesystem_avail_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\) / sum\(node_filesystem_size_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\)\)',
            DISK_PCT_CLUSTER,
        ),
        (
            r'\(sum\(node_filesystem_size_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\) - sum\(node_filesystem_avail_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\)\) / 1024\^3',
            DISK_USED_CLUSTER,
        ),
        (
            r'sum\(node_filesystem_size_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\) / 1024\^3',
            DISK_TOTAL_CLUSTER,
        ),
        (
            r'\(100 \* \(1 - sum by \(instance\) \(node_filesystem_avail_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\) / sum by \(instance\) \(node_filesystem_size_bytes\{fstype=~"ext4\|xfs\|vat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\)\)\)',
            None,
        ),
    ]
    # Per-node patterns (with JOIN suffix)
    per_node_old_pct = (
        r'\(100 \* \(1 - sum by \(instance\) \(node_filesystem_avail_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",'
        r'mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\) / sum by \(instance\) '
        r'\(node_filesystem_size_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\)\)\) '
        r'\* on\(instance\) group_left\(node\) label_replace\(kube_node_info, "instance", "\$1:9100", "internal_ip", "\(\.\*\)"\)'
    )
    per_node_old_used = (
        r'\(\(sum by \(instance\) \(node_filesystem_size_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\) - '
        r'sum by \(instance\) \(node_filesystem_avail_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\)\) / 1024\^3\) '
        r'\* on\(instance\) group_left\(node\) label_replace\(kube_node_info, "instance", "\$1:9100", "internal_ip", "\(\.\*\)"\)'
    )
    per_node_old_total = (
        r'\(sum by \(instance\) \(node_filesystem_size_bytes\{fstype=~"ext4\|xfs\|vfat\|ext2\|btrfs",mountpoint!~"/boot\.\*\|/run/credentials\.\*"\}\) / 1024\^3\) '
        r'\* on\(instance\) group_left\(node\) label_replace\(kube_node_info, "instance", "\$1:9100", "internal_ip", "\(\.\*\)"\)'
    )
    text = re.sub(per_node_old_pct, DISK_PCT_NODE, text)
    text = re.sub(per_node_old_used, DISK_USED_NODE, text)
    text = re.sub(per_node_old_total, DISK_TOTAL_NODE, text)
    for pattern, repl in replacements:
        if repl:
            text = re.sub(pattern, repl, text)
    return text


def patch_panel(panel: dict) -> None:
    pid = panel.get("id")
    ptype = panel.get("type")

    if pid in STAT_LAYOUT:
        x, y = STAT_LAYOUT[pid]
        panel["gridPos"] = {"x": x, "y": y, "w": STAT_W, "h": STAT_H}
        if pid in EXPR_BY_ID:
            panel["targets"][0]["expr"] = EXPR_BY_ID[pid]
        if pid == 111:
            panel["description"] = (
                "Per-block-device totals (deduped), all scraped nodes. "
                "Engine includes internal HDD + /srv/homelab/external."
            )
        if pid == 109:
            panel["description"] = (
                "Cluster-wide physical disk use. Each block device counted once per node "
                "(bind mounts excluded)."
            )
        if ptype == "gauge":
            panel.setdefault("options", {})["orientation"] = "auto"
            panel["options"]["reduceOptions"] = {
                "calcs": ["lastNotNull"],
                "fields": "",
                "values": False,
            }

    if pid == 112:
        panel["gridPos"] = {"x": 0, "y": 8, "w": 24, "h": 8}
        panel["targets"][0]["expr"] = DISK_PCT_NODE
    elif pid == 113:
        panel["gridPos"] = {"x": 0, "y": 16, "w": 24, "h": 8}
        panel["targets"][0]["expr"] = DISK_USED_NODE
    elif pid == 108:
        panel["gridPos"] = {"x": 0, "y": 7, "w": 24, "h": 1}
    elif pid == 101:
        panel["gridPos"] = {"x": 0, "y": 24, "w": 24, "h": 1}
    elif pid == 10:
        panel["gridPos"] = {"x": 0, "y": 25, "w": 24, "h": 8}
    elif pid == 102:
        panel["gridPos"] = {"x": 0, "y": 33, "w": 24, "h": 1}
    elif pid == 11:
        panel["gridPos"] = {"x": 0, "y": 34, "w": 24, "h": 8}
    elif pid == 103:
        panel["gridPos"] = {"x": 0, "y": 42, "w": 24, "h": 1}
    elif pid == 12:
        panel["gridPos"] = {"x": 0, "y": 43, "w": 12, "h": 8}
    elif pid == 13:
        panel["gridPos"] = {"x": 12, "y": 43, "w": 12, "h": 8}
    elif pid == 104:
        panel["gridPos"] = {"x": 0, "y": 51, "w": 24, "h": 1}
    elif pid in GPU_PANELS:
        panel["gridPos"] = {"x": GPU_PANELS[pid], "y": 52, "w": 8, "h": 8}
    elif pid == 105:
        panel["gridPos"] = {"x": 0, "y": 60, "w": 24, "h": 1}
    elif pid == 20:
        panel["gridPos"] = {"x": 0, "y": 61, "w": 24, "h": 10}
        for target in panel.get("targets", []):
            ref = target.get("refId", "")
            if ref == "diskpct":
                target["expr"] = DISK_PCT_NODE
            elif ref == "diskused":
                target["expr"] = DISK_USED_NODE
            elif ref == "disktotal":
                target["expr"] = DISK_TOTAL_NODE


def main() -> None:
    raw = DASH.read_text(encoding="utf-8")
    raw = replace_disk_exprs(raw)
    dash = json.loads(raw)

    for panel in dash["panels"]:
        patch_panel(panel)

    dash["version"] = dash.get("version", 1) + 1
    DASH.write_text(json.dumps(dash, indent=2) + "\n", encoding="utf-8")
    print(f"Patched {DASH} (version {dash['version']})")


if __name__ == "__main__":
    main()
