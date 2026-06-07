#!/usr/bin/env bash
# Query Prometheus disk totals (run on blackpearl).
set -euo pipefail
PROMIP="$(kubectl get pod -n monitoring prometheus-prometheus-stack-prometheus-0 -o jsonpath='{.status.podIP}')"
FS='{fstype=~"ext4|xfs|btrfs|ext2|vfat",mountpoint!~"/boot.*|/run/credentials.*|/var/lib/kubelet/.*|/mnt/wsl.*|^/mnt/c$|^/mnt/e$|^/host$"}'

query() {
  curl -sfG "http://${PROMIP}:9090/api/v1/query" --data-urlencode "query=$1" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); r=d["data"]["result"]; print(r[0]["value"][1] if r else "NO DATA")'
}

echo "Cluster disk total GB:"
query "sum(max by (instance, device) (node_filesystem_size_bytes${FS})) / 1024^3"
echo "Cluster disk used GB:"
query "(sum(max by (instance, device) (node_filesystem_size_bytes${FS})) - sum(max by (instance, device) (node_filesystem_avail_bytes${FS}))) / 1024^3"
echo "Cluster disk used %:"
query "100 * (1 - sum(max by (instance, device) (node_filesystem_avail_bytes${FS})) / sum(max by (instance, device) (node_filesystem_size_bytes${FS})))"
