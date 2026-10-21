#!/usr/bin/env bash
# Store blackpearl runner homelab SSH key in Vault (run after Vault is unsealed).
set -euo pipefail
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$HOME/launchpad/.env}"
KEY_FILE="${KEY_FILE:-/home/runner/.ssh/homelab}"
VAULT_PATH="${VAULT_PATH:-secret/sailblack/portfolio/homelab-ssh}"
set -a
# shellcheck disable=SC1090
source "$LAUNCHPAD_ENV"
set +a
export VAULT_ADDR="${VAULT_ADDR:-https://vault.klaut.pro}"
export VAULT_TOKEN="${VAULT_TOKEN:-${VAULT_ROOT_TOKEN:-}}"
unset VAULT_NAMESPACE
if ! vault status -format=json | jq -e ".sealed == false" >/dev/null; then
  echo "Vault is sealed; unseal first (see docs/vault-homelab.md)." >&2
  exit 1
fi
sudo test -r "$KEY_FILE"
priv=$(sudo cat "$KEY_FILE")
pub=$(sudo cat "${KEY_FILE}.pub")
vault kv put "$VAULT_PATH" \
  private_key="$priv" \
  public_key="$pub" \
  comment="runner@blackpearl-homelab" \
  deploy_user="s4il0r" \
  deploy_host="engine"
echo "Stored at $VAULT_PATH (private_key not printed)."
