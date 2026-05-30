#!/usr/bin/env bash
set -euo pipefail
PW=$(kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)
GRAF_URL="${GRAF_URL:-http://192.168.10.33:30300}"
JSON=$(curl -s -u "admin:${PW}" "${GRAF_URL}/api/dashboards/uid/homelab-cluster-resources")
python3 -c 'import sys,json; d=json.loads(sys.argv[1]); db=d["dashboard"]; print("title:", db.get("title")); print("uid:", db.get("uid")); print("refresh:", db.get("refresh")); print("panels:", len(db.get("panels", [])))' "$JSON"
echo "--- grafana.ini ---"
kubectl exec -n monitoring deploy/prometheus-stack-grafana -c grafana -- grep -E 'min_refresh|default_refresh' /etc/grafana/grafana.ini
echo "--- metrics ---"
kubectl exec -n monitoring deploy/prometheus-stack-grafana -c grafana -- wget -qO- \
  'http://prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query?query=100%20*%20%281%20-%20sum%28node_memory_MemAvailable_bytes%29%20%2F%20sum%28node_memory_MemTotal_bytes%29%29'
echo
kubectl exec -n monitoring deploy/prometheus-stack-grafana -c grafana -- wget -qO- \
  'http://prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query?query=count%28DCGM_FI_DEV_GPU_UTIL%29'
