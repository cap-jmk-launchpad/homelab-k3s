#!/usr/bin/env bash
set -euo pipefail
cp /tmp/kube-prometheus-stack-values.yaml ~/beelink-cleanup/k8s/monitoring/
GRAF_PW=$(kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' | base64 -d)
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f ~/beelink-cleanup/k8s/monitoring/kube-prometheus-stack-values.yaml \
  --set "grafana.adminPassword=${GRAF_PW}" \
  --no-hooks --wait --timeout 6m
kubectl delete pod -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase!=Running 2>/dev/null || true
sleep 40
PROM=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].status.podIP}')
echo "PROM=$PROM"
curl -sfG "http://${PROM}:9090/api/v1/label/cluster/values"
echo
curl -sfG "http://${PROM}:9090/api/v1/query" --data-urlencode 'query=up{job="kube-state-metrics"}' |
  python3 -c 'import json,sys; m=json.load(sys.stdin)["data"]["result"][0]["metric"]; print("ksm cluster=", m.get("cluster"))'
