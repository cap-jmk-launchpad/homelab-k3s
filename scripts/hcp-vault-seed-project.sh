#!/usr/bin/env bash
# Seed HCP Vault KV from a local .env file (never commit the .env).
#
# Usage:
#   ENV_FILE=/path/to/.env.staging ./scripts/hcp-vault-seed-project.sh <project> <env>
#
# Requires VAULT_ADDR + VAULT_TOKEN in repo .env (bootstrap/admin only).
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh" "$ROOT"

PROJECT="${1:-}"
ENV="${2:-}"
ENV_FILE="${ENV_FILE:-}"

if [[ -z "$PROJECT" || -z "$ENV" ]]; then
  echo "Usage: ENV_FILE=/path/.env $0 <project> <env>" >&2
  exit 1
fi
if [[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
  echo "ERROR: set ENV_FILE to a readable .env file" >&2
  exit 1
fi

: "${VAULT_ADDR:?Set VAULT_ADDR in .env}"
: "${VAULT_TOKEN:?Set VAULT_TOKEN in .env}"
export VAULT_NAMESPACE="${VAULT_NAMESPACE:-admin}"

command -v vault >/dev/null || { echo "ERROR: vault CLI not found" >&2; exit 1; }

args=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$line" ]] && continue
  [[ "$line" != *=* ]] && continue
  key="${line%%=*}"
  val="${line#*=}"
  # Strip optional quotes
  val="${val%\"}"; val="${val#\"}"
  val="${val%\'}"; val="${val#\'}"
  [[ -z "$key" || -z "$val" ]] && continue
  args+=("${key}=${val}")
done <"$ENV_FILE"

if [[ ${#args[@]} -eq 0 ]]; then
  echo "ERROR: no KEY=value pairs found in ${ENV_FILE}" >&2
  exit 1
fi

VAULT_PATH="secret/saas/${PROJECT}/${ENV}"
echo "==> Writing ${#args[@]} keys to ${VAULT_PATH} (values not printed)"
vault kv put "$VAULT_PATH" "${args[@]}"
echo "==> Done. Verify: vault kv get -format=json ${VAULT_PATH} | jq '.data.data | keys'"
