#!/usr/bin/env bash
# Install External Secrets Operator on homelab k3s.
#
# Usage:
#   ./scripts/hcp-vault-install-eso.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
ESO_CHART_VERSION="${ESO_CHART_VERSION:-0.14.2}"

kubectl apply -f "$ROOT/k8s/vault/external-secrets/namespace.yaml"

helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update external-secrets

helm upgrade --install external-secrets external-secrets/external-secrets \
  -n "$ESO_NAMESPACE" \
  --version "$ESO_CHART_VERSION" \
  --set installCRDs=true \
  --wait --timeout 5m

kubectl apply -f "$ROOT/k8s/vault/external-secrets/eso-rbac.yaml"

echo "==> External Secrets Operator ready in namespace ${ESO_NAMESPACE}"
kubectl -n "$ESO_NAMESPACE" get pods
