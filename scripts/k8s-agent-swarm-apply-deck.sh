#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

require_secret() {
  kubectl get secret "$1" -n agent-swarm >/dev/null 2>&1 || {
    echo "ERROR: missing secret $1 ? run db-secret + app secret scripts first" >&2
    exit 1
  }
}

kubectl get node deck >/dev/null 2>&1 || { echo "ERROR: node deck not found" >&2; exit 1; }
require_secret agent-swarm-db-secrets
require_secret agent-swarm-secrets

if kubectl get node deck -o jsonpath='{.spec.unschedulable}' 2>/dev/null | grep -q true; then
  kubectl uncordon deck
fi

kubectl apply -k "$ROOT/k8s/agent-swarm/overlays/deck/"

kubectl -n agent-swarm wait --for=condition=ready pod -l app=postgres --timeout=300s
if kubectl -n agent-swarm get job agent-swarm-db-migrate >/dev/null 2>&1; then
  kubectl -n agent-swarm wait --for=condition=complete job/agent-swarm-db-migrate --timeout=600s
fi
kubectl -n agent-swarm rollout status deployment/postgrest --timeout=300s
kubectl -n agent-swarm rollout status deployment/agents-dashboard --timeout=600s
kubectl -n agent-swarm get pods -o wide
echo ""
echo "Dashboard: http://192.168.10.26:30477/"
