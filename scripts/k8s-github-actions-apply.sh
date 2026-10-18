#!/usr/bin/env bash
# Install ARC controller + org runner scale sets for Majico, Librebase, Obsevia.
# Runners schedule only on k8s node "engine" — do not register github-actions runners on MacBook/laptops.
#
# Usage:
#   ./scripts/k8s-github-actions-apply.sh
#   GITHUB_ACTIONS_REMOTE=1 STAGING_HOST=blackpearl ./scripts/k8s-github-actions-apply.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/scripts/lib/load-env.sh" ]]; then
  # shellcheck source=lib/load-env.sh
  source "$ROOT/scripts/lib/load-env.sh" "$ROOT"
fi

REMOTE="${GITHUB_ACTIONS_REMOTE:-0}"
STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$ROOT/../blackpearl}"
REMOTE_DIR="${GITHUB_ACTIONS_REMOTE_DIR:-$HOME/homelab-k3s}"

CONTROLLER_NS="${ARC_CONTROLLER_NAMESPACE:-arc-systems}"
RUNNERS_NS="${GITHUB_ACTIONS_NAMESPACE:-github-actions}"
CONTROLLER_CHART="oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller"
SCALE_SET_CHART="oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set"
CONTROLLER_RELEASE="${ARC_CONTROLLER_RELEASE:-arc}"

require_helm() {
  command -v helm >/dev/null 2>&1 || {
    echo "ERROR: helm required — install https://helm.sh" >&2
    exit 1
  }
}

require_secret() {
  kubectl get secret "$1" -n "$RUNNERS_NS" >/dev/null 2>&1 || {
    echo "ERROR: missing secret $1 in $RUNNERS_NS — run scripts/k8s-github-actions-secret.sh" >&2
    exit 1
  }
}

sync_remote() {
  command -v rsync >/dev/null 2>&1 || {
    echo "ERROR: rsync required for GITHUB_ACTIONS_REMOTE=1" >&2
    exit 1
  }
  local ssh_opts=(-i "$STAGING_KEY" -o IdentitiesOnly=yes)
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" "mkdir -p ${REMOTE_DIR}/k8s/github-actions/values ${REMOTE_DIR}/scripts"
  rsync -az -e "ssh ${ssh_opts[*]}" \
    "$ROOT/k8s/github-actions/" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/github-actions/"
  rsync -az -e "ssh ${ssh_opts[*]}" \
    "$ROOT/scripts/k8s-github-actions-apply.sh" \
    "$ROOT/scripts/k8s-github-actions-secret.sh" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/"
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" \
    "cd ${REMOTE_DIR} && GITHUB_ACTIONS_REMOTE=0 ./scripts/k8s-github-actions-apply.sh"
  exit 0
}

if [[ "$REMOTE" == "1" ]]; then
  sync_remote
fi

require_helm

kubectl apply -f "$ROOT/k8s/github-actions/namespace.yaml"

helm upgrade --install "$CONTROLLER_RELEASE" "$CONTROLLER_CHART" \
  --namespace "$CONTROLLER_NS" \
  --create-namespace \
  --wait \
  --timeout 10m

install_scale_set() {
  local release="$1"
  local values="$2"
  local secret="$3"
  require_secret "$secret"
  helm upgrade --install "$release" "$SCALE_SET_CHART" \
    --namespace "$RUNNERS_NS" \
    --create-namespace \
    -f "$values" \
    --wait \
    --timeout 10m
}

install_scale_set arc-majico "$ROOT/k8s/github-actions/values/majico-xyz.yaml" majico-xyz-arc
install_scale_set arc-librebase "$ROOT/k8s/github-actions/values/librebase-official.yaml" librebase-official-arc
install_scale_set arc-obsevia "$ROOT/k8s/github-actions/values/obsevia-compliance.yaml" obsevia-compliance-arc

echo "ARC controller: namespace $CONTROLLER_NS release $CONTROLLER_RELEASE"
echo "Scale sets: namespace $RUNNERS_NS (majico-homelab, librebase-homelab, obsevia-homelab)"
kubectl get autoscalingrunnersets -n "$RUNNERS_NS" 2>/dev/null || kubectl get pods -n "$RUNNERS_NS"
