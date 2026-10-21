#!/usr/bin/env bash
# Print export lines for Azure OpenAI from homelab Vault (for Grok / local shells).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAULT_PATH="${VAULT_PATH:-secret/grokbot/azure}"

# shellcheck source=lib/vault-env.sh
source "$ROOT/scripts/lib/vault-env.sh"
load_vault_env "$ROOT"
export VAULT_TOKEN="${VAULT_TOKEN:-${VAULT_ROOT_TOKEN:-}}"
unset VAULT_NAMESPACE
if [[ -z "${VAULT_ADDR:-}" ]] || [[ "${VAULT_ADDR}" == https://vault.klaut.pro* ]]; then
  if vault status -address=http://127.0.0.1:30485 -format=json >/dev/null 2>&1; then
    export VAULT_ADDR=http://127.0.0.1:30485
  fi
fi

vault kv get -format=json "$VAULT_PATH" | python3 -c '
import json, sys
data = json.load(sys.stdin)["data"]["data"]
for k in sorted(data):
    if k == "NOTES":
        continue
    v = data[k].replace("\"", "\\\"")
    print(f"export {k}=\"{v}\"")
'
