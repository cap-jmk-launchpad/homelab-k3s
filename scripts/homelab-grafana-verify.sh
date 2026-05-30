#!/usr/bin/env bash
set -euo pipefail
curl -sf -u admin:HomelabGraf2026! \
  'http://127.0.0.1:30300/api/dashboards/uid/efa86fd1d0c121a26444b636a3f509a8' |
  python3 -c '
import json, sys
d = json.load(sys.stdin)
v = [x for x in d["dashboard"]["templating"]["list"] if x["name"] == "cluster"][0]
print("cluster var current:", v.get("current"))
print("cluster options:", len(v.get("options", [])))
for o in v.get("options", [])[:3]:
    print(" ", o)
'
POD=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | awk '{print $1}')
echo "Grafana pod: $POD"
kubectl exec -n monitoring "$POD" -c grafana -- env | grep GF_DASHBOARDS || echo "(no GF_DASHBOARDS env on running pod)"
kubectl get cm -n monitoring prometheus-stack-grafana -o yaml | grep -A3 '\[dashboards\]'
