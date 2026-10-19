#!/usr/bin/env bash
# Install ARC controller + org runner scale sets (scale set name: home-k3s).
# One Helm release per org in namespace gha-<org> (same runnerScaleSetName is OK across namespaces).
# Runners schedule only on k8s node "engine".
#
# Usage:
#   export KUBECONFIG=$HOME/.kube/config-homelab
#   ./scripts/k8s-github-actions-secret.sh
#   ./scripts/k8s-github-actions-apply.sh
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
CONTROLLER_CHART="oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller"
SCALE_SET_CHART="oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set"
CONTROLLER_RELEASE="${ARC_CONTROLLER_RELEASE:-arc}"

# helm release | k8s namespace | values file | secret name
SCALE_SETS=(
  "arc-cap-jmk-launchpad|gha-cap-jmk-launchpad|cap-jmk-launchpad.yaml|cap-jmk-launchpad-arc"
  "arc-majico|gha-majico-xyz|majico-xyz.yaml|majico-xyz-arc"
  "arc-librebase|gha-librebase-official|librebase-official.yaml|librebase-official-arc"
  "arc-obsevia|gha-obsevia-compliance|obsevia-compliance.yaml|obsevia-compliance-arc"
  "arc-sailblack|gha-sailblack|sailblack.yaml|sailblack-arc"
  "arc-taktwerk|gha-taktwerk|taktwerk.yaml|taktwerk-arc"
)

require_helm() {
  command -v helm >/dev/null 2>&1 || {
    echo "ERROR: helm required — install https://helm.sh" >&2
    exit 1
  }
}

require_secret() {
  local ns="$1" secret="$2"
  kubectl get secret "$secret" -n "$ns" >/dev/null 2>&1 || {
    echo "ERROR: missing secret $secret in $ns — run scripts/k8s-github-actions-secret.sh" >&2
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
  local release="$1" ns="$2" values="$3" secret="$4"
  require_secret "$ns" "$secret"
  helm upgrade --install "$release" "$SCALE_SET_CHART" \
    --namespace "$ns" \
    --create-namespace \
    -f "$ROOT/k8s/github-actions/values/$values" \
    --wait \
    --timeout 10m
}

installed=0
skipped=0
for entry in "${SCALE_SETS[@]}"; do
  IFS='|' read -r release ns values secret <<<"$entry"
  if ! kubectl get secret "$secret" -n "$ns" >/dev/null 2>&1; then
    echo "WARN: skip $release — no secret $secret in $ns" >&2
    skipped=$((skipped + 1))
    continue
  fi
  install_scale_set "$release" "$ns" "$values" "$secret"
  installed=$((installed + 1))
done

echo "ARC controller: namespace $CONTROLLER_NS release $CONTROLLER_RELEASE"
echo "Scale sets installed: $installed (skipped $skipped — add tokens via k8s-github-actions-secret.sh)"
kubectl get autoscalingrunnersets -A 2>/dev/null || true
