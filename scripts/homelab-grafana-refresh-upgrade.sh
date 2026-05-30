#!/usr/bin/env bash
# Apply grafana.ini refresh intervals via helm (run on blackpearl).
set -euo pipefail
REPO_ROOT="${REPO_ROOT:-$HOME/beelink-cleanup}"
GRAF_PW=$(kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f "${REPO_ROOT}/k8s/monitoring/kube-prometheus-stack-values.yaml" \
  --set "grafana.adminPassword=${GRAF_PW}"
echo "Waiting for Grafana rollout..."
kubectl rollout status deploy/prometheus-stack-grafana -n monitoring --timeout=120s
kubectl exec -n monitoring deploy/prometheus-stack-grafana -c grafana -- grep -E 'min_refresh|refresh_intervals' /etc/grafana/grafana.ini || true
