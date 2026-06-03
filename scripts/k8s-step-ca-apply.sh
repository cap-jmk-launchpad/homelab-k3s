#!/usr/bin/env bash
# Deploy step-ca internal PKI (PVC + ACME, NodePort 30484).
#
# Usage:
#   ./scripts/k8s-step-ca-apply.sh
#   STEP_CA_REMOTE=1 STAGING_HOST=blackpearl ./scripts/k8s-step-ca-apply.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/scripts/lib/load-env.sh" ]]; then
  # shellcheck source=lib/load-env.sh
  source "$ROOT/scripts/lib/load-env.sh" "$ROOT"
fi

REMOTE="${STEP_CA_REMOTE:-0}"
STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$ROOT/../blackpearl}"
REMOTE_DIR="${STEP_CA_REMOTE_DIR:-$HOME/homelab-k3s}"
STEP_CA_NAMESPACE="${STEP_CA_NAMESPACE:-step-ca}"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"

load_launchpad_env() {
  [[ -f "$LAUNCHPAD_ENV" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  sed '1s/^\xEF\xBB\xBF//; s/\r$//' "$LAUNCHPAD_ENV" >"$tmp"
  set -a
  # shellcheck disable=SC1090
  source "$tmp"
  set +a
  rm -f "$tmp"
}

load_launchpad_env

require_secret() {
  kubectl get secret "$1" -n "$STEP_CA_NAMESPACE" >/dev/null 2>&1 || {
    echo "ERROR: missing secret $1 — run scripts/k8s-step-ca-secret.sh first" >&2
    exit 1
  }
}

sync_remote() {
  command -v rsync >/dev/null 2>&1 || {
    echo "ERROR: rsync required for STEP_CA_REMOTE=1" >&2
    exit 1
  }
  local ssh_opts=(-i "$STAGING_KEY" -o IdentitiesOnly=yes)
  local launchpad_env="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" \
    "mkdir -p ${REMOTE_DIR}/k8s/step-ca ${REMOTE_DIR}/scripts ~/launchpad"
  rsync -az \
    -e "ssh ${ssh_opts[*]}" \
    "$ROOT/k8s/step-ca/" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/step-ca/"
  rsync -az \
    -e "ssh ${ssh_opts[*]}" \
    "$ROOT/scripts/k8s-step-ca-secret.sh" \
    "$ROOT/scripts/k8s-step-ca-apply.sh" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/"
  if [[ -f "$launchpad_env" ]]; then
    rsync -az -e "ssh ${ssh_opts[*]}" "$launchpad_env" \
      "${STAGING_USER}@${STAGING_HOST}:~/launchpad/.env"
  fi
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" \
    "chmod +x ${REMOTE_DIR}/scripts/k8s-step-ca-*.sh"
}

wait_ready() {
  kubectl -n "$STEP_CA_NAMESPACE" rollout status deployment/step-ca --timeout=180s
}

apply_local() {
  require_secret step-ca-secrets

  echo "==> apply step-ca stack (namespace $STEP_CA_NAMESPACE)"
  kubectl apply -k "$ROOT/k8s/step-ca/"

  wait_ready

  kubectl -n "$STEP_CA_NAMESPACE" get pods,svc,pvc
  local np="${STEP_CA_NODEPORT:-30484}"
  echo ""
  echo "In-cluster ACME: https://step-ca.${STEP_CA_NAMESPACE}.svc.cluster.local:9000/acme/acme/directory"
  echo "LAN NodePort:    https://192.168.10.33:${np}/health"
  echo "LAN hostname:    https://ca.homelab.lan/acme/acme/directory (needs Fritz/local DNS → .33)"
  echo ""
  echo "Export root CA for client trust:"
  echo "  kubectl -n ${STEP_CA_NAMESPACE} exec deploy/step-ca -- step ca root > homelab-root-ca.crt"
  echo ""
  echo "Docs: docs/internal-ca-homelab.md"
}

if [[ "$REMOTE" == "1" ]]; then
  sync_remote
  ssh -i "$STAGING_KEY" -o IdentitiesOnly=yes "${STAGING_USER}@${STAGING_HOST}" bash -s <<EOF
set -euo pipefail
cd ${REMOTE_DIR}
export LAUNCHPAD_ENV="\${LAUNCHPAD_ENV:-\$HOME/launchpad/.env}"
./scripts/k8s-step-ca-secret.sh
ROOT="${REMOTE_DIR}" STEP_CA_REMOTE=0 ./scripts/k8s-step-ca-apply.sh
EOF
else
  apply_local
fi
