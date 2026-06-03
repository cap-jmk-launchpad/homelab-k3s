#!/usr/bin/env bash
# Sync HCP Vault manifests/scripts to blackpearl and run install steps.
#
# Usage (from homelab-k3s on your PC):
#   ./scripts/hcp-vault-apply-remote.sh install-eso
#   ./scripts/hcp-vault-apply-remote.sh configure-auth
#   ./scripts/hcp-vault-apply-remote.sh onboard
#   ./scripts/hcp-vault-apply-remote.sh all
#
# Requires: scp, ssh, STAGING_* in .env or launchpad/.env
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh" "$ROOT"

STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$ROOT/../blackpearl}"
REMOTE_DIR="${HCP_VAULT_REMOTE_DIR:-$HOME/homelab-k3s}"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"

ssh_opts=(-i "$STAGING_KEY" -o IdentitiesOnly=yes)
ssh_cmd=(ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}")
scp_cmd=(scp "${ssh_opts[@]}")

sync_remote() {
  "${ssh_cmd[@]}" "mkdir -p ${REMOTE_DIR}/k8s/vault ${REMOTE_DIR}/scripts/lib ~/launchpad"
  "${scp_cmd[@]}" -r "$ROOT/k8s/vault" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/"
  for f in hcp-vault-install-eso.sh hcp-vault-configure-k8s-auth.sh \
    hcp-vault-onboard-project.sh hcp-vault-seed-project.sh hcp-vault-apply-remote.sh; do
    "${scp_cmd[@]}" "$ROOT/scripts/$f" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/"
  done
  "${scp_cmd[@]}" "$ROOT/scripts/lib/load-env.sh" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/lib/"
  if [[ -f "$LAUNCHPAD_ENV" ]]; then
    "${scp_cmd[@]}" "$LAUNCHPAD_ENV" "${STAGING_USER}@${STAGING_HOST}:~/launchpad/.env"
  fi
  "${ssh_cmd[@]}" "chmod +x ${REMOTE_DIR}/scripts/hcp-vault-*.sh"
  # homelab-k3s scripts read repo .env; mirror launchpad secrets there without committing
  if [[ -f "$LAUNCHPAD_ENV" ]]; then
    "${scp_cmd[@]}" "$LAUNCHPAD_ENV" "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/.env"
  fi
}

run_remote() {
  local step="$1"
  "${ssh_cmd[@]}" bash -s <<EOF
set -euo pipefail
cd ${REMOTE_DIR}
export LAUNCHPAD_ENV=\$HOME/launchpad/.env
case "${step}" in
  install-eso)
    ./scripts/hcp-vault-install-eso.sh
    ;;
  configure-auth)
    ./scripts/hcp-vault-configure-k8s-auth.sh
    ;;
  onboard)
    ./scripts/hcp-vault-onboard-project.sh sec-agent staging sec-agent
    ./scripts/hcp-vault-onboard-project.sh search-api prod search-gateway
    ./scripts/hcp-vault-onboard-project.sh vault-api prod klaut-platform
    ;;
  apply-store)
    if [[ ! -f k8s/vault/external-secrets/cluster-secret-store.yaml ]]; then
      echo "ERROR: create cluster-secret-store.yaml from example (set VAULT_ADDR) first" >&2
      exit 1
    fi
    kubectl apply -f k8s/vault/external-secrets/cluster-secret-store.yaml
    kubectl apply -f k8s/vault/projects/sec-agent/external-secret.yaml
    kubectl apply -f k8s/vault/projects/search-gateway/external-secret.yaml
    kubectl apply -f k8s/vault/projects/klaut-platform/external-secret.yaml
    ;;
  all)
    ./scripts/hcp-vault-install-eso.sh
    ./scripts/hcp-vault-configure-k8s-auth.sh
    ./scripts/hcp-vault-onboard-project.sh sec-agent staging sec-agent
    ./scripts/hcp-vault-onboard-project.sh search-api prod search-gateway
    ./scripts/hcp-vault-onboard-project.sh vault-api prod klaut-platform
    if [[ -f k8s/vault/external-secrets/cluster-secret-store.yaml ]]; then
      kubectl apply -f k8s/vault/external-secrets/cluster-secret-store.yaml
      kubectl apply -f k8s/vault/projects/sec-agent/external-secret.yaml \
        k8s/vault/projects/search-gateway/external-secret.yaml \
        k8s/vault/projects/klaut-platform/external-secret.yaml
    fi
    ;;
  *)
    echo "Unknown step: ${step}" >&2
    exit 1
    ;;
esac
EOF
}

STEP="${1:-install-eso}"
echo "==> Syncing vault tree to ${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}"
sync_remote
echo "==> Running ${STEP} on ${STAGING_HOST}"
run_remote "$STEP"
