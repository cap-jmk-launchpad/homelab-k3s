#!/usr/bin/env bash
set -euo pipefail
PROM_URL="${PROM_URL:-http://10.42.1.22:9090}"
query() {
  curl -sfG "${PROM_URL}/api/v1/query" --data-urlencode "query=$1" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); r=d["data"]["result"]; print(r[0]["value"][1] if r else "NO DATA")'
}
echo "memory util no cluster filter:" 
query '1 - sum(:node_memory_MemAvailable_bytes:sum) / sum(node_memory_MemTotal_bytes{job="node-exporter"})'
echo "memory util cluster empty:"
query '1 - sum(:node_memory_MemAvailable_bytes:sum{cluster=""}) / sum(node_memory_MemTotal_bytes{job="node-exporter",cluster=""})'
echo "cluster label values:"
curl -sfG "${PROM_URL}/api/v1/label/cluster/values"
echo
echo "ksm up metrics:"
curl -sfG "${PROM_URL}/api/v1/query" --data-urlencode 'query=up{job="kube-state-metrics"}' | python3 -m json.tool | head -30
