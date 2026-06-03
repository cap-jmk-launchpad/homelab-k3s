#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh" "$ROOT"
# shellcheck source=lib/vault-env.sh
source "$ROOT/scripts/lib/vault-env.sh"
LOCAL_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"
STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$ROOT/homelab}"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
ssh -i "$STAGING_KEY" -o IdentitiesOnly=yes "${STAGING_USER}@${STAGING_HOST}" "cat ~/launchpad/.env" >"$tmp"
touch "$LOCAL_ENV"
merged=0
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"; line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ "$line" != *=* ]] && continue
  key="${line%%=*}"; val="${line#*=}"
  case "$key" in VAULT_ADDR|VAULT_TOKEN|VAULT_NAMESPACE|HCP_CLIENT_ID|HCP_CLIENT_SECRET) ;; *) continue ;; esac
  [[ -n "$val" ]] || continue
  if vault_env_upsert "$LOCAL_ENV" "$key" "$val" 0; then merged=1; echo "==> merged ${key}"; fi
done <"$tmp"
[[ "$merged" -eq 1 ]] || echo "No non-empty VAULT_* on remote."
