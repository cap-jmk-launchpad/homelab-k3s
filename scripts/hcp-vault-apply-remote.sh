#!/usr/bin/env bash
# Sync HCP Vault manifests/scripts to blackpearl and run install steps.
#
# Usage:
#   ./scripts/hcp-vault-apply-remote.sh install-eso
#   ./scripts/hcp-vault-apply-remote.sh configure-auth
#   ./scripts/hcp-vault-apply-remote.sh render-store
#   ./scripts/hcp-vault-apply-remote.sh apply-store
#   ./scripts/hcp-vault-apply-remote.sh vault-edge
#   ./scripts/hcp-vault-apply-remote.sh all
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh" "$ROOT"

STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$ROOT/homelab}"
# Git Bash on Windows often lacks mDNS; prefer LAN IP from .env when set.
if ! getent hosts "$STAGING_HOST" >/dev/null 2>&1 && [[ -n "${BLACKPEARL_DHCP_IP:-}" ]]; then
  STAGING_HOST="${BLACKPEARL_DHCP_IP}"
fi
REMOTE_DIR="${HCP_VAULT_REMOTE_DIR:-$HOME/homelab-k3s}"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"

ssh_opts=(-i "$STAGING_KEY" -o IdentitiesOnly=yes)
ssh_cmd=(ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}")
scp_cmd=(scp "${ssh_opts[@]}")

sync_remote() {
  "${ssh_cmd[@]}" "mkdir -p ${REMOTE_DIR}/k8s/vault ${REMOTE_DIR}/k8s/edge ${REMOTE_DIR}/scripts/lib ~/launchpad"
  "${scp_cmd[@]}" -r "$ROOT/k8s/vault" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/"
  "${scp_cmd[@]}" "$ROOT/k8s/edge/Caddyfile" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/edge/"
  for f in hcp-vault-install-eso.sh hcp-vault-install-cli.sh hcp-vault-configure-k8s-auth.sh \
    hcp-vault-onboard-project.sh hcp-vault-seed-project.sh hcp-vault-apply-remote.sh \
    hcp-vault-render-cluster-store.sh hcp-vault-ensure-kv-placeholders.sh \
    hcp-vault-bootstrap-from-portal.sh edge-vault-klaut-status.sh edge-caddy-apply.sh; do
    "${scp_cmd[@]}" "$ROOT/scripts/$f" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/"
  done
  for f in load-env.sh vault-env.sh; do
    "${scp_cmd[@]}" "$ROOT/scripts/lib/$f" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/lib/"
  done
  if [[ -f "$LAUNCHPAD_ENV" ]]; then
    "${scp_cmd[@]}" "$LAUNCHPAD_ENV" "${STAGING_USER}@${STAGING_HOST}:~/launchpad/.env"
    "${scp_cmd[@]}" "$LAUNCHPAD_ENV" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/.env"
  fi
  "${ssh_cmd[@]}" "chmod +x ${REMOTE_DIR}/scripts/hcp-vault-*.sh ${REMOTE_DIR}/scripts/edge-*.sh ${REMOTE_DIR}/scripts/edge-caddy-apply.sh"
}

run_remote() {
  local step="$1"
  "${ssh_cmd[@]}" bash -s <<EOF
set -euo pipefail
cd ~/homelab-k3s
export LAUNCHPAD_ENV=\$HOME/launchpad/.env
case "${step}" in
  install-eso) ./scripts/hcp-vault-install-eso.sh ;;
  install-cli) ./scripts/hcp-vault-install-cli.sh ;;
  configure-auth)
    ./scripts/hcp-vault-install-cli.sh
    ./scripts/hcp-vault-configure-k8s-auth.sh
    ;;
  render-store) ./scripts/hcp-vault-render-cluster-store.sh ;;
  seed-placeholders) ./scripts/hcp-vault-ensure-kv-placeholders.sh ;;
  onboard)
    ./scripts/hcp-vault-onboard-project.sh sec-agent staging sec-agent
    ./scripts/hcp-vault-onboard-project.sh search-api prod search-gateway
    ./scripts/hcp-vault-onboard-project.sh vault-api prod klaut-platform
    ;;
  apply-store)
    ./scripts/hcp-vault-render-cluster-store.sh
    kubectl apply -f k8s/vault/external-secrets/cluster-secret-store.yaml
    kubectl apply -f k8s/vault/projects/sec-agent/external-secret.yaml
    kubectl apply -f k8s/vault/projects/search-gateway/external-secret.yaml
    kubectl apply -f k8s/vault/projects/klaut-platform/external-secret.yaml
    sudo REPO_ROOT=~/homelab-k3s ./scripts/edge-vault-klaut-status.sh
    sudo bash ./scripts/edge-caddy-apply.sh
    ;;
  vault-edge)
    sudo REPO_ROOT=~/homelab-k3s ./scripts/edge-vault-klaut-status.sh
    sudo bash ./scripts/edge-caddy-apply.sh
    ;;
  all)
    ./scripts/hcp-vault-install-eso.sh
    ./scripts/hcp-vault-install-cli.sh
    ./scripts/hcp-vault-configure-k8s-auth.sh
    ./scripts/hcp-vault-onboard-project.sh sec-agent staging sec-agent
    ./scripts/hcp-vault-onboard-project.sh search-api prod search-gateway
    ./scripts/hcp-vault-onboard-project.sh vault-api prod klaut-platform
    ./scripts/hcp-vault-render-cluster-store.sh
    ./scripts/hcp-vault-ensure-kv-placeholders.sh
    kubectl apply -f k8s/vault/external-secrets/cluster-secret-store.yaml
    kubectl apply -f k8s/vault/projects/sec-agent/external-secret.yaml \
      k8s/vault/projects/search-gateway/external-secret.yaml \
      k8s/vault/projects/klaut-platform/external-secret.yaml
    sudo REPO_ROOT=~/homelab-k3s ./scripts/edge-vault-klaut-status.sh
    sudo bash ./scripts/edge-caddy-apply.sh
    ;;
  *) echo "Unknown step: ${step}" >&2; exit 1 ;;
esac
EOF
}

STEP="${1:-install-eso}"
echo "==> Syncing vault tree to ${STAGING_USER}@${STAGING_HOST}"
sync_remote
echo "==> Running ${STEP} on ${STAGING_HOST}"
run_remote "$STEP"
