#!/usr/bin/env bash
# Deploy agent-swarm to Raspberry Pi deck (kustomize overlay).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

kubectl get node deck >/dev/null 2>&1 || {
  echo "ERROR: node 'deck' not found in cluster" >&2
  exit 1
}

if kubectl get node deck -o jsonpath='{.spec.unschedulable}' 2>/dev/null | grep -q true; then
  echo "==> uncordon deck"
  kubectl uncordon deck
fi

kubectl apply -k "$ROOT/k8s/agent-swarm/overlays/deck/"
kubectl -n agent-swarm rollout status deployment/agents-dashboard --timeout=600s

echo ""
kubectl -n agent-swarm get pods -o wide
echo ""
echo "Dashboard: http://192.168.10.26:30477/"
echo "Health:    curl -sf http://192.168.10.26:30477/api/health"
