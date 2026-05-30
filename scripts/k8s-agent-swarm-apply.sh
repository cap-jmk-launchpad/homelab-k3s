#!/usr/bin/env bash
# Apply agent-swarm kustomize and wait for dashboard rollout.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
kubectl apply -k "$ROOT/k8s/agent-swarm/"
kubectl -n agent-swarm rollout status deployment/agents-dashboard --timeout=300s
kubectl -n agent-swarm get pods,svc
echo ""
echo "Dashboard (NodePort): http://<node-ip>:30477/"
echo "Health: curl -sf http://<node-ip>:30477/api/health"
