#!/usr/bin/env bash
# Check Grafana refresh intervals config (run on blackpearl).
set -euo pipefail
POD=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
echo "Grafana pod: $POD"
kubectl exec -n monitoring "$POD" -- cat /etc/grafana/grafana.ini 2>/dev/null |
  grep -E 'refresh|min_interval' || echo "(no refresh settings in grafana.ini)"
kubectl exec -n monitoring "$POD" -- env 2>/dev/null | grep -iE 'GF_.*REFRESH|GF_DASHBOARDS' || true
