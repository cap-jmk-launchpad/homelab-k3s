#!/usr/bin/env bash
# Fix node-exporter (desktop WSL + engine USB mounts). Run on blackpearl.
set -euo pipefail

REPO="${REPO:-$HOME/beelink-cleanup}"
NS=monitoring
VALUES="${REPO}/k8s/monitoring/kube-prometheus-stack-values.yaml"

GRAF_PW="$(kubectl get secret prometheus-stack-grafana -n "${NS}" -o jsonpath='{.data.admin-password}' | base64 -d)"

echo "==> Helm upgrade (node-exporter: no hostRootFs, no /srv/homelab — WSL-safe)"
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n "${NS}" \
  -f "${VALUES}" \
  --set "grafana.adminPassword=${GRAF_PW}" \
  --reset-values \
  --no-hooks \
  --timeout 3m

echo "==> Engine /srv/homelab filesystem exporter (:9101)"
kubectl apply -f "${REPO}/k8s/monitoring/engine-homelab-fs-exporter.yaml"

echo "==> Desktop WSL node-exporter (/proc/1/root, no rshared /)"
kubectl apply -f "${REPO}/k8s/monitoring/desktop-node-exporter-wsl.yaml"

echo "==> Restart node-exporter pods"
kubectl rollout restart daemonset/prometheus-stack-prometheus-node-exporter -n "${NS}"
kubectl rollout status daemonset/prometheus-stack-prometheus-node-exporter -n "${NS}" --timeout=3m || true

echo "==> Node-exporter pods"
kubectl get pods -n "${NS}" -l app.kubernetes.io/name=prometheus-node-exporter -o wide

echo "==> Coverage check"
python3 "${REPO}/scripts/prom-node-coverage.py" 2>/dev/null || python3 /tmp/prom-node-coverage.py

echo "==> Deploy Grafana dashboards"
bash "${REPO}/scripts/homelab-deploy-dashboards.sh"

echo "Done."
