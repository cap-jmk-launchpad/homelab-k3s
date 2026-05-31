#!/usr/bin/env bash
# Deploy Loki + Alloy log stack on homelab k3s (run on blackpearl).
set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/beelink-cleanup}"
MON_DIR="${MON_DIR:-$REPO_DIR/k8s/monitoring}"

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

echo "==> Engine host path (run once on engine if missing):"
echo "    sudo mkdir -p /srv/homelab/loki && sudo chown -R 10001:10001 /srv/homelab/loki"

kubectl apply -f "${MON_DIR}/loki-engine-pv.yaml"

helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install loki grafana/loki \
  -n monitoring \
  -f "${MON_DIR}/loki-values.yaml" \
  --wait --timeout 10m

kubectl apply -f "${MON_DIR}/alloy-daemonset.yaml"

echo "==> Upgrade Grafana stack to provision Loki datasource (uid loki)..."
GRAF_PW="$(kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)"
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f "${MON_DIR}/kube-prometheus-stack-values.yaml" \
  --set "grafana.adminPassword=${GRAF_PW}" \
  --no-hooks --wait --timeout 6m

echo "==> Provision Grafana dashboards (sidecar ConfigMaps)..."
bash "${REPO_DIR}/scripts/homelab-deploy-dashboards.sh"

echo ""
echo "Loki: http://loki.monitoring.svc:3100 (in-cluster)"
echo "Grafana Explore: http://$(hostname -I | awk '{print $1}'):30300/explore?left={\"datasource\":\"loki\"}"
echo "Dashboard: /d/homelab-pod-logs/homelab-pod-logs"
