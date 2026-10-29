#!/usr/bin/env bash
# Copy secret/grokbot/azure from homelab Vault into Hetzner Vault (vault.sail.black / hz-majico-prod).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$HOME/launchpad/.env}"
HOMELAB_PATH="${HOMELAB_PATH:-secret/grokbot/azure}"
HETZNER_HOST="${HETZNER_HOST:-root@2.31.25.5}"
HETZNER_SSH_KEY="${HETZNER_SSH_KEY:-$HOME/.ssh/majico_vps}"

: "${VAULT_ADMIN_TOKEN_HETZNER:?Set VAULT_ADMIN_TOKEN_HETZNER (root or write on secret/grokbot/*)}"

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

json="$(vault kv get -format=json "$HOMELAB_PATH")"
remote_script="$(VAULT_ADMIN_TOKEN_HETZNER="$VAULT_ADMIN_TOKEN_HETZNER" python3 - "$json" <<'PY'
import json, os, shlex, sys
data = json.loads(sys.argv[1])["data"]["data"]
lines = ["set -euo pipefail"]
for k, v in data.items():
    if k == "NOTES":
        continue
    lines.append(f"export {k}={shlex.quote(v)}")
lines.append(f"export VAULT_ADMIN_TOKEN={shlex.quote(os.environ['VAULT_ADMIN_TOKEN_HETZNER'])}")
lines.append("/usr/local/sbin/vault-put-grokbot-azure.sh")
print("\n".join(lines))
PY
)"

ssh -o BatchMode=yes -i "$HETZNER_SSH_KEY" "$HETZNER_HOST" bash -s <<<"$remote_script"
echo "OK: Hetzner secret/grokbot/azure"
