#!/usr/bin/env python3
"""Fix disk PromQL: closing parens + remove $ anchors for Grafana."""
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DASH = REPO / "k8s/monitoring/homelab-cluster-resources-dashboard.json"

FS = (
    'fstype=~"ext4|xfs|btrfs|ext2|vfat",'
    'mountpoint!~"/boot.*|/run/credentials.*|/var/lib/kubelet/.*|/mnt/wsl.*|/mnt/c|/mnt/e|/host"'
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


def main() -> None:
    dash = json.loads(DASH.read_text(encoding="utf-8"))
    for panel in dash["panels"]:
        pid = panel.get("id")
        for target in panel.get("targets", []):
            expr = target.get("expr", "")
            if "node_filesystem_" not in expr:
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

    dash["version"] = dash.get("version", 4) + 1
    DASH.write_text(json.dumps(dash, indent=2) + "\n", encoding="utf-8")
    print(f"Fixed {DASH} -> v{dash['version']}")
    print("cluster_pct:", EXPR["cluster_pct"])


if __name__ == "__main__":
    main()
