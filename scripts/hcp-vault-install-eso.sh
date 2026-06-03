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
# Homelab: service ClusterIP (10.43.0.1) is unreachable from many pods — use hostNetwork.
ESO_HOST_NETWORK="${ESO_HOST_NETWORK:-true}"
ESO_NODE_HOSTNAME="${ESO_NODE_HOSTNAME:-blackpearl}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"

kubectl apply -f "$ROOT/k8s/vault/external-secrets/namespace.yaml"

helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update external-secrets

helm_args=(
  upgrade --install external-secrets external-secrets/external-secrets
  -n "$ESO_NAMESPACE"
  --version "$ESO_CHART_VERSION"
  --set installCRDs=true
  --set "nodeSelector.kubernetes\.io/hostname=${ESO_NODE_HOSTNAME}"
  --wait --timeout "$HELM_TIMEOUT"
)
if [[ "$ESO_HOST_NETWORK" == "true" ]]; then
  # ClusterIP 10.43.0.1 is unreachable from pods/host on this k3s — use local apiserver.
  helm_args+=(
    --set hostNetwork=true
    --set certController.hostNetwork=true
    --set webhook.hostNetwork=true
    --set "certController.nodeSelector.kubernetes\.io/hostname=${ESO_NODE_HOSTNAME}"
    --set "webhook.nodeSelector.kubernetes\.io/hostname=${ESO_NODE_HOSTNAME}"
    --set-json 'env=[{"name":"KUBERNETES_SERVICE_HOST","value":"127.0.0.1"},{"name":"KUBERNETES_SERVICE_PORT","value":"6443"}]'
    --set-json 'certController.env=[{"name":"KUBERNETES_SERVICE_HOST","value":"127.0.0.1"},{"name":"KUBERNETES_SERVICE_PORT","value":"6443"}]'
    --set-json 'webhook.env=[{"name":"KUBERNETES_SERVICE_HOST","value":"127.0.0.1"},{"name":"KUBERNETES_SERVICE_PORT","value":"6443"}]'
  )
fi
helm "${helm_args[@]}"

kubectl apply -f "$ROOT/k8s/vault/external-secrets/eso-rbac.yaml"

echo "==> External Secrets Operator ready in namespace ${ESO_NAMESPACE}"
kubectl -n "$ESO_NAMESPACE" get pods
