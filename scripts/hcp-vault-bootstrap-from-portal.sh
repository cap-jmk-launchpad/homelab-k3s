#!/usr/bin/env bash
# One-time HCP Vault bootstrap: prompt for cluster URL + admin token, write launchpad/.env.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/vault-env.sh
source "$ROOT/scripts/lib/vault-env.sh"

LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"
[[ -f "$LAUNCHPAD_ENV" ]] || LAUNCHPAD_ENV="${HOME}/launchpad/.env"
mkdir -p "$(dirname "$LAUNCHPAD_ENV")"
touch "$LAUNCHPAD_ENV"
load_vault_env "$ROOT"

echo "HCP Vault bootstrap → ${LAUNCHPAD_ENV}"
echo "KV data stays in HCP; token rotation does not wipe secret/ paths."
echo ""

if [[ -n "${VAULT_ADDR:-}" && -n "${VAULT_TOKEN:-}" && "${VAULT_REGENERATE:-0}" != 1 ]]; then
  echo "VAULT_ADDR and VAULT_TOKEN already set. Use VAULT_REGENERATE=1 to replace."
  exit 0
fi

if [[ -z "${VAULT_ADDR:-}" || "${VAULT_REGENERATE:-0}" == 1 ]]; then
  read -r -p "VAULT_ADDR (HCP public cluster URL): " new_addr
  new_addr="$(echo "$new_addr" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "$new_addr" ]] || { echo "ERROR: VAULT_ADDR required" >&2; exit 1; }
  vault_env_upsert "$LAUNCHPAD_ENV" VAULT_ADDR "$new_addr" "${VAULT_REGENERATE:-0}" || true
  export VAULT_ADDR="$new_addr"
fi

if [[ -z "${VAULT_TOKEN:-}" || "${VAULT_REGENERATE:-0}" == 1 ]]; then
  read -r -s -p "VAULT_TOKEN (admin, bootstrap only): " new_tok
  echo ""
  [[ -n "$new_tok" ]] || { echo "ERROR: VAULT_TOKEN required" >&2; exit 1; }
  vault_env_upsert "$LAUNCHPAD_ENV" VAULT_TOKEN "$new_tok" "${VAULT_REGENERATE:-0}" || true
fi

vault_env_upsert "$LAUNCHPAD_ENV" VAULT_NAMESPACE "${VAULT_NAMESPACE:-admin}" 0 || true
echo "Done. Next: hcp-vault-apply-remote.sh configure-auth"
