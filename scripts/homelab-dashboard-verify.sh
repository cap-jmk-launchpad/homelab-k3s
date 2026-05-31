#!/usr/bin/env bash
# Verify homelab Grafana dashboards are provisioned (run on blackpearl).
set -euo pipefail

PW=$(kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)
GRAF_URL="${GRAF_URL:-http://192.168.10.41:30300}"

check_uid() {
  local uid="$1"
  local label="$2"
  JSON=$(curl -sf -u "admin:${PW}" "${GRAF_URL}/api/dashboards/uid/${uid}")
  python3 -c 'import sys,json; d=json.loads(sys.argv[1]); db=d["dashboard"]; print(sys.argv[2]+":", db.get("title"), "uid="+db.get("uid"))' "$JSON" "$label"
}

echo "==> ConfigMaps with grafana_dashboard=1:"
kubectl get cm -n monitoring -l grafana_dashboard=1 -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp

echo "==> Dashboard API checks:"
check_uid homelab-cluster-resources "cluster-resources"
check_uid homelab-gpu-dcgm "gpu"
check_uid homelab-pod-logs "pod-logs"
