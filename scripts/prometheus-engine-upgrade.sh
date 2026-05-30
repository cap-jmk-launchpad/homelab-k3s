#!/usr/bin/env bash
set -euo pipefail

kubectl apply -f /tmp/prometheus-engine-pv.yaml

GRAF_PW="$(kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)"

helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f /tmp/kube-prometheus-stack-values.yaml \
  --set "grafana.adminPassword=${GRAF_PW}" \
  --wait \
  --timeout 10m

echo "--- post-upgrade ---"
helm status prometheus-stack -n monitoring | grep -E 'STATUS|REVISION|LAST DEPLOYED'
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus -o wide
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.retention}{" retentionSize="}{.items[0].spec.retentionSize}{"\n"}'
