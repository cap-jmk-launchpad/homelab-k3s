#!/usr/bin/env bash
# Deploy SigNoz + k8s-infra on homelab k3s (run on blackpearl).
set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/beelink-cleanup}"
MON_DIR="${MON_DIR:-$REPO_DIR/k8s/monitoring}"
NS=signoz
RELEASE=signoz
INFRA_RELEASE=signoz-k8s-infra

kubectl create namespace "${NS}" --dry-run=client -o yaml | kubectl apply -f -

helm repo add signoz https://charts.signoz.io 2>/dev/null || true
helm repo update

echo "==> SigNoz core (ClickHouse, query, UI, collector)..."
helm upgrade --install "${RELEASE}" signoz/signoz \
  -n "${NS}" \
  -f "${MON_DIR}/signoz-values.yaml" \
  --wait --timeout 25m

echo "==> k8s-infra (DaemonSet log/metric agents on all nodes)..."
helm upgrade --install "${INFRA_RELEASE}" signoz/k8s-infra \
  -n "${NS}" \
  -f "${MON_DIR}/signoz-k8s-infra-values.yaml" \
  --wait --timeout 15m

echo ""
echo "==> Pod status (${NS})"
kubectl get pods -n "${NS}" -o wide
kubectl get svc -n "${NS}" signoz signoz-otel-collector 2>/dev/null || kubectl get svc -n "${NS}"

LAN_IP="$(hostname -I | awk '{print $1}')"
echo ""
echo "SigNoz UI:  http://${LAN_IP}:30301"
echo "OTLP gRPC:  signoz-otel-collector.${NS}.svc.cluster.local:4317"
echo "OTLP HTTP:  signoz-otel-collector.${NS}.svc.cluster.local:4318"
echo ""
echo "Logs: SigNoz k8s-infra (presets.logsCollection). See docs/homelab-signoz.md"
