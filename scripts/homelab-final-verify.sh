#!/usr/bin/env bash
set -euo pipefail
PROM_URL="${PROM_URL:-http://10.42.1.22:9090}"
echo "=== Prometheus health ==="
curl -sf "${PROM_URL}/-/healthy" && echo OK || echo FAIL
echo "=== node count ==="
curl -sfG "${PROM_URL}/api/v1/query" --data-urlencode 'query=count(node_memory_MemTotal_bytes)'
echo
echo "=== cluster memory % ==="
curl -sfG "${PROM_URL}/api/v1/query" --data-urlencode 'query=100 * (1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))'
echo
echo "=== cluster label values ==="
curl -sfG "${PROM_URL}/api/v1/label/cluster/values"
echo
GRAF_PW=$(kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)
echo "=== Grafana cluster variable ==="
curl -sf -u "admin:${GRAF_PW}" \
  'http://127.0.0.1:30300/api/dashboards/uid/efa86fd1d0c121a26444b636a3f509a8' |
  python3 -c '
import json, sys
d = json.load(sys.stdin)
v = [x for x in d["dashboard"]["templating"]["list"] if x["name"] == "cluster"][0]
print("current:", v.get("current"))
print("options:", v.get("options"))
'
echo "=== Grafana pods ==="
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana
