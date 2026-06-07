#!/usr/bin/env python3
import json
import subprocess
import sys

FS = (
    'fstype=~"ext4|xfs|btrfs|ext2|vfat",'
    'mountpoint!~"/boot.*|/run/credentials.*|/var/lib/kubelet/.*|/mnt/wsl.*|^/mnt/c$|^/mnt/e$|^/host$"'
)

QUERIES = {
    "count_raw": f"count(node_filesystem_size_bytes{{{FS}}})",
    "cluster_pct_nested": (
        f"100 * (1 - sum(max by (instance, device) (node_filesystem_avail_bytes{{{FS}}})) "
        f"/ sum(max by (instance, device) (node_filesystem_size_bytes{{{FS}}})))"
    ),
    "cluster_pct_simple": (
        f"100 * (1 - sum(node_filesystem_avail_bytes{{{FS}}}) "
        f"/ sum(node_filesystem_size_bytes{{{FS}}}))"
    ),
    "cluster_pct_device_sum": (
        f"100 * (1 - sum by (instance) (sum by (instance, device) (node_filesystem_avail_bytes{{{FS}}})) "
        f"/ sum by (instance) (sum by (instance, device) (node_filesystem_size_bytes{{{FS}}})))"
    ),
    "cluster_pct_max_device": (
        f"100 * (1 - sum(sum by (instance, device) (node_filesystem_avail_bytes{{{FS}}})) "
        f"/ sum(sum by (instance, device) (node_filesystem_size_bytes{{{FS}}})))"
    ),
}

if __name__ == "__main__":
    prom = subprocess.check_output(
        [
            "kubectl",
            "get",
            "pod",
            "-n",
            "monitoring",
            "prometheus-prometheus-stack-prometheus-0",
            "-o",
            "jsonpath={.status.podIP}",
        ],
        text=True,
    ).strip()
    for name, q in QUERIES.items():
        out = subprocess.check_output(
            ["curl", "-sfG", f"http://{prom}:9090/api/v1/query", "--data-urlencode", f"query={q}"],
            text=True,
        )
        data = json.loads(out)["data"]["result"]
        print(f"{name}: {len(data)} series", end="")
        if data:
            print(f" -> {data[0]['value'][1]}")
        else:
            print(" -> NO DATA")
