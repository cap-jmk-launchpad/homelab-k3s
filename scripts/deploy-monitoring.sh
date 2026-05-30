#!/usr/bin/env bash
# Run on blackpearl as s4il0r. Requires Helm 3 and kubectl.
set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/beelink-cleanup}"
MON_DIR="${MON_DIR:-$REPO_DIR/k8s/monitoring}"

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

if [[ ! -f /tmp/monitoring-secrets.env ]]; then
  GRAFANA_PW=$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)
  echo "GRAFANA_ADMIN_PASSWORD=${GRAFANA_PW}" > /tmp/monitoring-secrets.env
  chmod 600 /tmp/monitoring-secrets.env
  echo "Generated Grafana password (also in /tmp/monitoring-secrets.env)"
fi
# shellcheck source=/dev/null
source /tmp/monitoring-secrets.env

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f "${MON_DIR}/kube-prometheus-stack-values.yaml" \
  --set "grafana.adminPassword=${GRAFANA_ADMIN_PASSWORD}" \
  --wait --timeout 10m

kubectl patch deployment metrics-server -n kube-system --type=json \
  --patch-file="${MON_DIR}/metrics-server-patch.json" || true

kubectl apply -f "${MON_DIR}/dcgm-exporter.yaml"

echo "Grafana: http://$(hostname -I | awk '{print $1}'):30300  user=admin"
echo "Password: ${GRAFANA_ADMIN_PASSWORD}"
