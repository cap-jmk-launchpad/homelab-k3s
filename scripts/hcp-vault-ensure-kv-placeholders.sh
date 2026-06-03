#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/vault-env.sh
source "$ROOT/scripts/lib/vault-env.sh"
load_vault_env "$ROOT"
: "${VAULT_ADDR:?}"; : "${VAULT_TOKEN:?}"
export VAULT_NAMESPACE="${VAULT_NAMESPACE:-admin}"
command -v vault >/dev/null || { echo "ERROR: run hcp-vault-install-cli.sh" >&2; exit 1; }
vault secrets enable -version=2 -path=secret kv 2>/dev/null || true
for vp in saas/sec-agent/staging saas/search-api/prod saas/vault-api/prod; do
  vault kv get "secret/${vp}" >/dev/null 2>&1 && { echo "==> secret/${vp} exists"; continue; }
  vault kv put "secret/${vp}" _placeholder=configure-me
  echo "==> placeholder secret/${vp}"
done
