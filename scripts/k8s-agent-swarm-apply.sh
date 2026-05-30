#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

require_secret() {
  kubectl get secret "$1" -n agent-swarm >/dev/null 2>&1 || {
    echo "ERROR: missing secret $1 ? run db-secret + app secret scripts first" >&2
    exit 1
  }
}

require_secret agent-swarm-db-secrets
require_secret agent-swarm-secrets

echo "==> wait for postgres"
kubectl -n agent-swarm wait --for=condition=ready pod -l app=postgres --timeout=300s 2>/dev/null || true

kubectl apply -k "$ROOT/k8s/agent-swarm/"

echo "==> wait for migrate job"
if kubectl -n agent-swarm get job agent-swarm-db-migrate >/dev/null 2>&1; then
  kubectl -n agent-swarm wait --for=condition=complete job/agent-swarm-db-migrate --timeout=600s
fi
echo "==> wait for postgrest"
kubectl -n agent-swarm rollout status deployment/postgrest --timeout=300s
kubectl -n agent-swarm rollout status deployment/agents-dashboard --timeout=600s
kubectl -n agent-swarm get pods,svc
echo ""
echo "Dashboard: http://<node-ip>:30477/"
echo "PostgREST: http://<node-ip>:30421/rest/v1/"
