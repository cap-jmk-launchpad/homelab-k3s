#!/usr/bin/env bash
# Provision homelab Grafana dashboards via sidecar ConfigMaps (run on blackpearl).
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/beelink-cleanup}"
MON_DIR="${REPO_ROOT}/k8s/monitoring"
NS=monitoring

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

deploy_cm homelab-cluster-resources-dashboard homelab-cluster-resources-dashboard.json
deploy_cm homelab-gpu-dashboard homelab-gpu-dashboard.json

echo "Dashboard sidecar will reload within ~60s. Grafana: http://$(hostname -I | awk '{print $1}'):30300"
