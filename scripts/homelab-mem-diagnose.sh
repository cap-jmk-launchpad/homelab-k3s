#!/usr/bin/env bash
# Memory dashboard diagnostics (run on blackpearl).
set -euo pipefail
PROM_URL="${PROM_URL:-http://10.42.1.22:9090}"

query() {
  curl -sfG "${PROM_URL}/api/v1/query" --data-urlencode "query=$1" |
    python3 -c 'import json,sys; d=json.load(sys.stdin); r=d["data"]["result"]; print(r[0]["value"][1] if r else "no data")'
}

echo "=== node count ==="
query 'count(node_memory_MemTotal_bytes)'

echo "=== cluster memory % (node-exporter) ==="
query '100 * (1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))'

echo "=== cluster MemTotal bytes ==="
query 'sum(node_memory_MemTotal_bytes)'

echo "=== cluster MemUsed bytes ==="
query 'sum(node_memory_MemTotal_bytes) - sum(node_memory_MemAvailable_bytes)'

echo "=== container working set sum (kubelet/cAdvisor) ==="
query 'sum(container_memory_working_set_bytes{container!="",container!="POD"})'

echo "=== per-node memory % ==="
curl -sfG "${PROM_URL}/api/v1/query" \
  --data-urlencode 'query=100 * (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)' |
  python3 -c '
import json, sys
d = json.load(sys.stdin)
for x in sorted(d["data"]["result"], key=lambda z: z["metric"].get("instance", "")):
    m = x["metric"]
    inst = m.get("instance", "?")
    node = m.get("nodename", m.get("node", "?"))
    pct = float(x["value"][1])
    print("  %s (%s): %.1f%%" % (inst, node, pct))
'

echo "=== dashboard cluster-total memory panels ==="
kubectl get cm -n monitoring prometheus-stack-k8s-resources-cluster \
  -o jsonpath='{.data.k8s-resources-cluster.json}' |
  python3 -c '
import json, sys
d = json.load(sys.stdin)
for p in d.get("panels", []):
    title = p.get("title", "")
    if "mem" not in title.lower() and "Mem" not in title:
        continue
    for t in p.get("targets", []):
        expr = t.get("expr", "")[:200]
        print("  [%s] %s" % (title, expr))
'

echo "=== cluster variable label values ==="
curl -sfG "${PROM_URL}/api/v1/label/cluster/values" | python3 -c 'import json,sys; print(json.load(sys.stdin))'

echo "=== dashboard memory util (no cluster filter) ==="
query '1 - sum(:node_memory_MemAvailable_bytes:sum) / sum(node_memory_MemTotal_bytes{job="node-exporter"})'

echo "=== dashboard memory util (cluster=\"\") ==="
query '1 - sum(:node_memory_MemAvailable_bytes:sum{cluster=""}) / sum(node_memory_MemTotal_bytes{job="node-exporter",cluster=""})'

echo "=== kube-state-metrics cluster labels ==="
curl -sfG "${PROM_URL}/api/v1/query" --data-urlencode 'query=up{job="kube-state-metrics"}' |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print([x["metric"] for x in d["data"]["result"]])'

echo "=== node-exporter cluster labels sample ==="
curl -sfG "${PROM_URL}/api/v1/query" --data-urlencode 'query=node_memory_MemTotal_bytes{job="node-exporter"}' |
  python3 -c 'import json,sys; d=json.load(sys.stdin); [print(x["metric"].get("cluster","<no cluster>"), x["metric"].get("instance")) for x in d["data"]["result"][:5]]'
