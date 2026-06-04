#!/usr/bin/env bash
# Deploy Vault OSS (Raft + PVC) on homelab k3s.
#
# Usage:
#   ./scripts/k8s-vault-oss-apply.sh
#   VAULT_OSS_REMOTE=1 ./scripts/k8s-vault-oss-apply.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh" "$ROOT"

REMOTE="${VAULT_OSS_REMOTE:-0}"
STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$ROOT/../blackpearl}"
REMOTE_DIR="${VAULT_OSS_REMOTE_DIR:-$HOME/homelab-k3s}"
VAULT_NAMESPACE_K8S="${VAULT_NAMESPACE_K8S:-vault}"
VAULT_NODEPORT="${VAULT_NODEPORT:-30485}"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"

sync_remote() {
  command -v rsync >/dev/null 2>&1 || { echo "ERROR: rsync required" >&2; exit 1; }
  local ssh_opts=(-i "$STAGING_KEY" -o IdentitiesOnly=yes)
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" \
    "mkdir -p ${REMOTE_DIR}/k8s/vault/server ${REMOTE_DIR}/scripts/lib ~/launchpad"
  rsync -az -e "ssh ${ssh_opts[*]}" \
    "$ROOT/k8s/vault/server/" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/vault/server/"
  for f in k8s-vault-oss-apply.sh k8s-vault-oss-init.sh k8s-vault-oss-secret.sh; do
    rsync -az -e "ssh ${ssh_opts[*]}" \
      "$ROOT/scripts/$f" \
      "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/"
  done
  rsync -az -e "ssh ${ssh_opts[*]}" \
    "$ROOT/scripts/lib/vault-env.sh" "$ROOT/scripts/lib/load-env.sh" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/lib/"
  if [[ -f "$LAUNCHPAD_ENV" ]]; then
    rsync -az -e "ssh ${ssh_opts[*]}" "$LAUNCHPAD_ENV" \
      "${STAGING_USER}@${STAGING_HOST}:~/launchpad/.env"
    rsync -az -e "ssh ${ssh_opts[*]}" "$LAUNCHPAD_ENV" \
      "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/.env"
  fi
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" \
    "chmod +x ${REMOTE_DIR}/scripts/k8s-vault-oss-*.sh"
}

apply_local() {
  echo "==> Applying Vault OSS (namespace ${VAULT_NAMESPACE_K8S}, node blackpearl)"
  kubectl apply -k "$ROOT/k8s/vault/server/"
  kubectl -n "$VAULT_NAMESPACE_K8S" rollout status statefulset/vault --timeout=300s 2>/dev/null || \
    kubectl -n "$VAULT_NAMESPACE_K8S" wait --for=jsonpath='{.status.phase}'=Running pod/vault-0 --timeout=300s
  kubectl -n "$VAULT_NAMESPACE_K8S" get pods,svc,pvc
  echo ""
  echo "In-cluster: http://vault.${VAULT_NAMESPACE_K8S}.svc:8200"
  echo "LAN NodePort: http://127.0.0.1:${VAULT_NODEPORT}/ui"
  echo ""
  echo "Next: ./scripts/k8s-vault-oss-init.sh"
}

if [[ "$REMOTE" == "1" ]]; then
  sync_remote
  ssh -i "$STAGING_KEY" -o IdentitiesOnly=yes "${STAGING_USER}@${STAGING_HOST}" bash -s <<EOF
set -euo pipefail
cd ${REMOTE_DIR}
export LAUNCHPAD_ENV="\${LAUNCHPAD_ENV:-\$HOME/launchpad/.env}"
ROOT="${REMOTE_DIR}" VAULT_OSS_REMOTE=0 ./scripts/k8s-vault-oss-apply.sh
ROOT="${REMOTE_DIR}" ./scripts/k8s-vault-oss-init.sh
EOF
else
  apply_local
fi
