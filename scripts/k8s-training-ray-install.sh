#!/usr/bin/env bash
# Install KubeRay operator (once per cluster). Idempotent.
set -euo pipefail

if ! command -v helm >/dev/null 2>&1; then
  echo "ERROR: helm not found — install Helm 3 first" >&2
  exit 1
fi

helm repo add kuberay https://ray-project.github.io/kuberay-helm/ 2>/dev/null || true
helm repo update kuberay

if helm status kuberay-operator -n ray-system >/dev/null 2>&1; then
  echo "==> kuberay-operator already installed"
else
  echo "==> installing kuberay-operator"
  helm install kuberay-operator kuberay/kuberay-operator -n ray-system --create-namespace
fi

kubectl -n ray-system rollout status deployment/kuberay-operator --timeout=300s
kubectl get crd rayclusters.ray.io
echo ""
echo "Deploy cluster: kubectl apply -f k8s/training/ray/raycluster.yaml"
