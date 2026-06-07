#!/usr/bin/env bash
# Sync Vault OSS + ESO stack to blackpearl and run deploy steps.
#
# Usage:
#   ./scripts/k8s-vault-oss-apply-remote.sh server          # Raft deploy + init
#   ./scripts/k8s-vault-oss-apply-remote.sh install-eso
#   ./scripts/k8s-vault-oss-apply-remote.sh configure-auth
#   ./scripts/k8s-vault-oss-apply-remote.sh render-store
#   ./scripts/k8s-vault-oss-apply-remote.sh onboard
#   ./scripts/k8s-vault-oss-apply-remote.sh apply-store
#   ./scripts/k8s-vault-oss-apply-remote.sh vault-edge
#   ./scripts/k8s-vault-oss-apply-remote.sh all
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh" "$ROOT"

STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$ROOT/../blackpearl}"
if ! getent hosts "$STAGING_HOST" >/dev/null 2>&1 && [[ -n "${BLACKPEARL_DHCP_IP:-}" ]]; then
  STAGING_HOST="${BLACKPEARL_DHCP_IP}"
fi
REMOTE_DIR="${VAULT_OSS_REMOTE_DIR:-$HOME/homelab-k3s}"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"

ssh_opts=(-i "$STAGING_KEY" -o IdentitiesOnly=yes)
ssh_cmd=(ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}")
scp_cmd=(scp "${ssh_opts[@]}")

sync_remote() {
  "${ssh_cmd[@]}" "mkdir -p ${REMOTE_DIR}/k8s/vault ${REMOTE_DIR}/k8s/edge ${REMOTE_DIR}/scripts/lib ~/launchpad"
  "${scp_cmd[@]}" -r "$ROOT/k8s/vault" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/"
  "${scp_cmd[@]}" -r "$ROOT/k8s/edge/" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/edge/"
  for f in k8s-vault-oss-apply.sh k8s-vault-oss-apply-remote.sh k8s-vault-oss-init.sh k8s-vault-oss-secret.sh \
    hcp-vault-install-eso.sh hcp-vault-configure-k8s-auth.sh hcp-vault-onboard-project.sh hcp-vault-seed-project.sh \
    vault-oss-render-cluster-store.sh edge-vault-klaut-status.sh edge-lis-apply.sh edge-lis-validate.sh lint-li-native.sh; do
    [[ -f "$ROOT/scripts/$f" ]] && "${scp_cmd[@]}" "$ROOT/scripts/$f" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/"
  done
  for f in load-env.sh vault-env.sh; do
    "${scp_cmd[@]}" "$ROOT/scripts/lib/$f" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/lib/"
  done
  if [[ -f "$LAUNCHPAD_ENV" ]]; then
    "${scp_cmd[@]}" "$LAUNCHPAD_ENV" "${STAGING_USER}@${STAGING_HOST}:~/launchpad/.env"
    "${scp_cmd[@]}" "$LAUNCHPAD_ENV" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/.env"
  fi
  "${ssh_cmd[@]}" "chmod +x ${REMOTE_DIR}/scripts/k8s-vault-oss-*.sh ${REMOTE_DIR}/scripts/hcp-vault-*.sh ${REMOTE_DIR}/scripts/vault-oss-*.sh ${REMOTE_DIR}/scripts/edge-*.sh"
}

run_remote() {
  local step="$1"
  "${ssh_cmd[@]}" bash -s <<EOF
set -euo pipefail
cd ${REMOTE_DIR}
export LAUNCHPAD_ENV=\$HOME/launchpad/.env
export VAULT_ADDR=\${VAULT_ADDR:-http://127.0.0.1:30485}
case "${step}" in
  server)
    ROOT="${REMOTE_DIR}" VAULT_OSS_REMOTE=0 ./scripts/k8s-vault-oss-apply.sh
    ROOT="${REMOTE_DIR}" ./scripts/k8s-vault-oss-init.sh
    ;;
  install-eso) ./scripts/hcp-vault-install-eso.sh ;;
  configure-auth) ./scripts/hcp-vault-configure-k8s-auth.sh ;;
  render-store) ./scripts/vault-oss-render-cluster-store.sh ;;
  onboard)
    ./scripts/hcp-vault-onboard-project.sh sec-agent staging sec-agent
    ./scripts/hcp-vault-onboard-project.sh search-api prod search-gateway
    ./scripts/hcp-vault-onboard-project.sh vault-api prod klaut-platform
    ;;
  apply-store)
    ./scripts/vault-oss-render-cluster-store.sh
    kubectl apply -f k8s/vault/external-secrets/cluster-secret-store.yaml
    kubectl apply -f k8s/vault/projects/sec-agent/external-secret.yaml
    kubectl apply -f k8s/vault/projects/search-gateway/external-secret.yaml
    kubectl apply -f k8s/vault/projects/klaut-platform/external-secret.yaml
    sudo REPO_ROOT=${REMOTE_DIR} ./scripts/edge-vault-klaut-status.sh
    sudo bash ./scripts/edge-lis-apply.sh
    ;;
  vault-edge)
    sudo REPO_ROOT=${REMOTE_DIR} ./scripts/edge-vault-klaut-status.sh
    sudo bash ./scripts/edge-lis-apply.sh
    ;;
  all)
    ROOT="${REMOTE_DIR}" VAULT_OSS_REMOTE=0 ./scripts/k8s-vault-oss-apply.sh
    ROOT="${REMOTE_DIR}" ./scripts/k8s-vault-oss-init.sh
    ./scripts/hcp-vault-install-eso.sh
    ./scripts/hcp-vault-configure-k8s-auth.sh
    ./scripts/hcp-vault-onboard-project.sh sec-agent staging sec-agent
    ./scripts/hcp-vault-onboard-project.sh search-api prod search-gateway
    ./scripts/hcp-vault-onboard-project.sh vault-api prod klaut-platform
    ./scripts/vault-oss-render-cluster-store.sh
    kubectl apply -f k8s/vault/external-secrets/cluster-secret-store.yaml
    kubectl apply -f k8s/vault/projects/sec-agent/external-secret.yaml \
      k8s/vault/projects/search-gateway/external-secret.yaml \
      k8s/vault/projects/klaut-platform/external-secret.yaml
    sudo REPO_ROOT=${REMOTE_DIR} ./scripts/edge-vault-klaut-status.sh
    sudo bash ./scripts/edge-lis-apply.sh
    ;;
  *) echo "Unknown step: ${step}" >&2; exit 1 ;;
esac
EOF
}

STEP="${1:-server}"
echo "==> Syncing to ${STAGING_USER}@${STAGING_HOST}"
sync_remote
echo "==> Running ${STEP}"
run_remote "$STEP"
