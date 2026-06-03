#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

require_secret() {
  kubectl get secret "$1" -n searxng >/dev/null 2>&1 || {
    echo "ERROR: missing secret $1 — run scripts/k8s-searxng-secret.sh first" >&2
    exit 1
  }
}

require_secret searxng-secrets

echo "==> apply searxng stack"
kubectl apply -k "$ROOT/k8s/searxng/"

echo "==> wait for valkey"
kubectl -n searxng rollout status deployment/valkey --timeout=120s

echo "==> wait for searxng"
kubectl -n searxng rollout status deployment/searxng --timeout=300s

kubectl -n searxng get pods,svc
echo ""
echo "NodePort: http://<blackpearl-ip>:30479/search?q=test&format=json"
echo "Edge:     https://search.klaut.pro/search?q=test&format=json (after DNS + edge-lis-apply)"
echo ""
echo "Next: rsync k8s/edge/ and run scripts/edge-lis-apply.sh on blackpearl"
