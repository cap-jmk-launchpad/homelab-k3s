#!/usr/bin/env bash
# Deploy OWASP Dependency-Track (Postgres + official Helm chart, NodePort 30482).
#
# Usage:
#   ./scripts/k8s-dependency-track-apply.sh
#   DEPTRACK_REMOTE=1 STAGING_HOST=blackpearl ./scripts/k8s-dependency-track-apply.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/scripts/lib/load-env.sh" ]]; then
  # shellcheck source=lib/load-env.sh
  source "$ROOT/scripts/lib/load-env.sh" "$ROOT"
fi

REMOTE="${DEPTRACK_REMOTE:-0}"
STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$ROOT/../blackpearl}"
REMOTE_DIR="${DEPTRACK_REMOTE_DIR:-$HOME/homelab-k3s}"
DEPTRACK_NAMESPACE="${DEPTRACK_NAMESPACE:-dependency-track}"
HELM_RELEASE="${DEPTRACK_HELM_RELEASE:-dependency-track}"

require_secret() {
  kubectl get secret "$1" -n "$DEPTRACK_NAMESPACE" >/dev/null 2>&1 || {
    echo "ERROR: missing secret $1 — run scripts/k8s-dependency-track-secret.sh first" >&2
    exit 1
  }
}

require_helm() {
  command -v helm >/dev/null 2>&1 || {
    echo "ERROR: helm not found — install Helm 3 on the apply host" >&2
    exit 1
  }
}

sync_remote() {
  command -v rsync >/dev/null 2>&1 || {
    echo "ERROR: rsync required for DEPTRACK_REMOTE=1" >&2
    exit 1
  }
  local ssh_opts=(-i "$STAGING_KEY" -o IdentitiesOnly=yes)
  local launchpad_env="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" \
    "mkdir -p ${REMOTE_DIR}/k8s/dependency-track ${REMOTE_DIR}/scripts ~/launchpad"
  rsync -az \
    -e "ssh ${ssh_opts[*]}" \
    "$ROOT/k8s/dependency-track/" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/dependency-track/"
  rsync -az \
    -e "ssh ${ssh_opts[*]}" \
    "$ROOT/scripts/k8s-dependency-track-secret.sh" \
    "$ROOT/scripts/k8s-dependency-track-apply.sh" \
    "$ROOT/scripts/k8s-dependency-track-configure-feeds.sh" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/"
  if [[ -f "$launchpad_env" ]]; then
    rsync -az -e "ssh ${ssh_opts[*]}" "$launchpad_env" \
      "${STAGING_USER}@${STAGING_HOST}:~/launchpad/.env"
  fi
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" \
    "chmod +x ${REMOTE_DIR}/scripts/k8s-dependency-track-*.sh"
}

apply_local() {
  require_helm
  require_secret dependency-track-secrets

  echo "==> postgres (namespace $DEPTRACK_NAMESPACE)"
  kubectl apply -f "$ROOT/k8s/dependency-track/namespace.yaml"
  kubectl apply -k "$ROOT/k8s/dependency-track/postgres/"
  kubectl -n "$DEPTRACK_NAMESPACE" rollout status statefulset/dependency-track-postgres --timeout=300s

  echo "==> helm repo + dependency-track chart"
  helm repo add dependency-track https://dependencytrack.github.io/helm-charts 2>/dev/null || true
  helm repo update dependency-track

  helm upgrade --install "$HELM_RELEASE" dependency-track/dependency-track \
    -n "$DEPTRACK_NAMESPACE" \
    --create-namespace \
    -f "$ROOT/k8s/dependency-track/helm-values.yaml" \
    --wait \
    --timeout 20m

  echo "==> wait for api-server (first boot: vulnerability mirrors 10–30+ min)"
  kubectl -n "$DEPTRACK_NAMESPACE" rollout status statefulset/dependency-track-api-server --timeout=1800s
  kubectl -n "$DEPTRACK_NAMESPACE" rollout status deployment/dependency-track-frontend --timeout=600s

  if [[ -x "$ROOT/scripts/k8s-dependency-track-configure-feeds.sh" ]]; then
    LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}" \
      "$ROOT/scripts/k8s-dependency-track-configure-feeds.sh" || true
  fi

  kubectl -n "$DEPTRACK_NAMESPACE" get pods,svc
  local np="${DEPTRACK_NODEPORT:-30482}"
  echo ""
  echo "NodePort UI:  http://192.168.10.33:${np}/  (login admin — change default password)"
  echo "In-cluster:   http://dependency-track-api-server.${DEPTRACK_NAMESPACE}.svc:8080"
  echo ""
  echo "Optional WAN: deps.klaut.pro — see docs/dependency-track-homelab.md + k8s/edge/homelab.httpd.toml"
}

if [[ "$REMOTE" == "1" ]]; then
  sync_remote
  ssh -i "$STAGING_KEY" -o IdentitiesOnly=yes "${STAGING_USER}@${STAGING_HOST}" bash -s <<EOF
set -euo pipefail
cd ${REMOTE_DIR}
export LAUNCHPAD_ENV="\${LAUNCHPAD_ENV:-\$HOME/launchpad/.env}"
./scripts/k8s-dependency-track-secret.sh
ROOT="${REMOTE_DIR}" DEPTRACK_REMOTE=0 ./scripts/k8s-dependency-track-apply.sh
EOF
else
  apply_local
fi
