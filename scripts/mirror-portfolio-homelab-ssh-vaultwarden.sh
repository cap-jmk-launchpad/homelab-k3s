#!/usr/bin/env bash
# Mirror secret/sailblack/portfolio/homelab-ssh from Vault into Vaultwarden (bw CLI).
# Prereq: bw login (org sail.black) and BW_SESSION or `bw unlock`.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$HOME/launchpad/.env}"
VAULT_PATH="${VAULT_PATH:-secret/sailblack/portfolio/homelab-ssh}"
COLLECTION_NAME="${VAULTWARDEN_COLLECTION:-Servers & Backups}"
ITEM_NAME="${VAULTWARDEN_ITEM_NAME:-portfolio blackpearl homelab SSH}"

command -v bw >/dev/null || { echo "Install Bitwarden CLI (bw) first." >&2; exit 1; }
command -v jq >/dev/null || { echo "jq required." >&2; exit 1; }

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

json="$(vault kv get -format=json "$VAULT_PATH")"
priv="$(jq -r '.data.data.private_key' <<<"$json")"
pub="$(jq -r '.data.data.public_key' <<<"$json")"
comment="$(jq -r '.data.data.comment // empty' <<<"$json")"

bw sync >/dev/null
org_id="$(bw list organizations | jq -r '.[] | select(.name=="sail.black") | .id' | head -1)"
[[ -n "$org_id" ]] || { echo "Org sail.black not found in bw." >&2; exit 1; }
coll_id="$(bw list collections --organizationid "$org_id" | jq -r --arg n "$COLLECTION_NAME" '.[] | select(.name==$n) | .id' | head -1)"
[[ -n "$coll_id" ]] || { echo "Collection \"$COLLECTION_NAME\" not found." >&2; exit 1; }

notes="comment: ${comment}
public_key:
${pub}"

template="$(bw get template item)"
item="$(jq -n \
  --arg name "$ITEM_NAME" \
  --arg notes "$notes" \
  --arg priv "$priv" \
  --argjson coll "$coll_id" \
  --argjson org "$org_id" \
  --argjson tpl "$template" \
  '$tpl | .organizationId=$org | .collectionIds=[$coll] | .name=$name | .notes=$notes | .login.username="runner@blackpearl-homelab" | .login.password=$priv | .login.uris=[]')"

enc="$(bw encode "$item")"
existing="$(bw list items --organizationid "$org_id" | jq -r --arg n "$ITEM_NAME" '.[] | select(.name==$n) | .id' | head -1)"
if [[ -n "$existing" ]]; then
  bw edit item "$existing" "$enc" >/dev/null
  echo "Updated Vaultwarden item: $ITEM_NAME"
else
  bw create item "$enc" >/dev/null
  echo "Created Vaultwarden item: $ITEM_NAME"
fi
