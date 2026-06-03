#!/usr/bin/env bash
# Create searxng-secrets (random SEARXNG_SECRET + optional metrics basic auth).
#
# Usage:
#   ./scripts/k8s-searxng-secret.sh
#
set -euo pipefail

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing $1" >&2
    exit 1
  }
}

require_cmd kubectl
require_cmd openssl

SECRET="$(openssl rand -hex 32)"
METRICS_USER="${SEARXNG_OPEN_METRICS_USER:-metrics}"
METRICS_SECRET="${SEARXNG_OPEN_METRICS_SECRET:-$(openssl rand -hex 16)}"

kubectl create namespace searxng --dry-run=client -o yaml | kubectl apply -f -

kubectl -n searxng delete secret searxng-secrets --ignore-not-found
kubectl -n searxng create secret generic searxng-secrets \
  --from-literal=SEARXNG_SECRET="$SECRET" \
  --from-literal=SEARXNG_OPEN_METRICS_USER="$METRICS_USER" \
  --from-literal=SEARXNG_OPEN_METRICS_SECRET="$METRICS_SECRET"

echo "==> secret searxng-secrets updated in namespace searxng"
echo "    metrics user: ${METRICS_USER}"
