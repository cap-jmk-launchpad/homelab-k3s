#!/usr/bin/env bash
set -euo pipefail

PF_PORT="${PF_PORT:-19090}"
BASE="http://127.0.0.1:${PF_PORT}"

query() {
  curl -sG "${BASE}/api/v1/query" --data-urlencode "query=$1"
}

echo "=== node_memory_MemTotal_bytes count ==="
query 'count(node_memory_MemTotal_bytes)'
echo

echo "=== sum MemTotal (bytes) ==="
query 'sum(node_memory_MemTotal_bytes)'
echo

echo "=== up{job=node-exporter} ==="
query 'up{job="node-exporter"}'
echo

echo "=== node-exporter targets ==="
curl -s "${BASE}/api/v1/targets" |
  python3 -c '
import json, sys
d = json.load(sys.stdin)
pool = "serviceMonitor/monitoring/prometheus-stack-prometheus-node-exporter/0"
for t in d["data"]["activeTargets"]:
    if t.get("scrapePool") != pool:
        continue
    inst = t["labels"].get("instance", "?")
    print(inst, t["health"], (t.get("lastError") or "")[:140])
'
