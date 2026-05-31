#!/usr/bin/env bash
# Provision homelab Grafana dashboards via sidecar ConfigMaps (run on blackpearl).
# Falls back to Grafana HTTP API if sidecar has not loaded a dashboard within ~60s.
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/beelink-cleanup}"
MON_DIR="${REPO_ROOT}/k8s/monitoring"
NS=monitoring
GRAF_URL="${GRAF_URL:-http://127.0.0.1:30300}"

deploy_cm() {
  local name="$1"
  local file="$2"
  kubectl create configmap "$name" \
    --from-file="${file%.json}.json=${MON_DIR}/${file}" \
    -n "$NS" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl label configmap "$name" -n "$NS" grafana_dashboard=1 --overwrite
  echo "Applied ConfigMap $name from ${file}"
}

dashboard_uid() {
  python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['uid'])" "$1"
}

dashboard_exists() {
  local uid="$1"
  curl -sf -u "admin:${GRAFANA_PW}" "${GRAF_URL}/api/dashboards/uid/${uid}" >/dev/null 2>&1
}

import_via_api() {
  local file="$1"
  local uid
  uid="$(dashboard_uid "${MON_DIR}/${file}")"
  echo "Importing ${uid} via Grafana API (sidecar fallback)..."
  python3 - "${MON_DIR}/${file}" <<'PY' | curl -sf -X POST -u "admin:${GRAFANA_PW}" \
    -H 'Content-Type: application/json' -d @- "${GRAF_URL}/api/dashboards/db"
import json, sys
with open(sys.argv[1]) as f:
    dash = json.load(f)
print(json.dumps({
    "dashboard": dash,
    "overwrite": True,
    "message": "homelab-deploy-dashboards.sh API fallback",
}))
PY
  echo "Imported ${uid} via API"
}

ensure_dashboard() {
  local file="$1"
  local uid
  uid="$(dashboard_uid "${MON_DIR}/${file}")"
  local tries=12
  while (( tries > 0 )); do
    if dashboard_exists "${uid}"; then
      echo "Dashboard ${uid} available in Grafana"
      return 0
    fi
    echo "Waiting for sidecar to load ${uid} (${tries} attempts left)..."
    sleep 5
    ((tries--)) || true
  done
  import_via_api "${file}"
}

GRAFANA_PW="$(kubectl get secret prometheus-stack-grafana -n "${NS}" -o jsonpath='{.data.admin-password}' | base64 -d)"

deploy_cm homelab-cluster-resources-dashboard homelab-cluster-resources-dashboard.json
deploy_cm homelab-gpu-dashboard homelab-gpu-dashboard.json
deploy_cm homelab-logs-dashboard homelab-logs-dashboard.json

echo "Checking dashboards in Grafana (${GRAF_URL})..."
ensure_dashboard homelab-cluster-resources-dashboard.json
ensure_dashboard homelab-gpu-dashboard.json
ensure_dashboard homelab-logs-dashboard.json

echo "Done. Grafana: ${GRAF_URL}"
echo "Pod logs dashboard: ${GRAF_URL}/d/homelab-pod-logs/homelab-pod-logs"
