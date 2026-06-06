#!/usr/bin/env bash
# One-shot cluster disk inventory (run on blackpearl).
set -euo pipefail

echo "=== PVs / PVCs (engine / prometheus) ==="
kubectl get pv,pvc -A 2>/dev/null | grep -E 'engine|prometheus|NAME' || true

echo
echo "=== Node storage capacity (kubelet) ==="
kubectl get nodes -o custom-columns=NAME:.metadata.name,STORAGE:.status.capacity.storage

echo
echo "=== Prometheus pod ==="
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o wide

PROM="$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true)"
echo "Prometheus IP: ${PROM:-none}"

FS='{fstype=~"ext4|xfs|vfat|ext2|btrfs",mountpoint!~"/boot.*|/run/credentials.*"}'

if [[ -n "${PROM}" ]]; then
  echo
  echo "=== Filesystems >= 1 GiB (node-exporter) ==="
  curl -sfG "http://${PROM}:9090/api/v1/query" \
    --data-urlencode "query=sum by (instance,mountpoint,device,fstype) (node_filesystem_size_bytes${FS})" |
    python3 -c '
import json, sys
d = json.load(sys.stdin)
for r in sorted(d["data"]["result"], key=lambda x: (x["metric"].get("instance", ""), x["metric"].get("mountpoint", ""))):
    m = r["metric"]
    gb = float(r["value"][1]) / 1024**3
    if gb >= 1:
        print(f"{m.get(\"instance\", \"?\"):22} {m.get(\"mountpoint\", \"?\"):20} {m.get(\"device\", \"?\"):12} {gb:8.1f} GB")
'

  echo
  echo "=== Cluster disk totals ==="
  curl -sfG "http://${PROM}:9090/api/v1/query" \
    --data-urlencode "query=sum(node_filesystem_size_bytes${FS})" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); r=d["data"]["result"]; print(f"total: {float(r[0][\"value\"][1])/1024**3:.1f} GB" if r else "NO DATA")'
  curl -sfG "http://${PROM}:9090/api/v1/query" \
    --data-urlencode "query=100 * (1 - sum(node_filesystem_avail_bytes${FS}) / sum(node_filesystem_size_bytes${FS}))" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); r=d["data"]["result"]; print(f"used %: {float(r[0][\"value\"][1]):.1f}" if r else "NO DATA")'
fi
