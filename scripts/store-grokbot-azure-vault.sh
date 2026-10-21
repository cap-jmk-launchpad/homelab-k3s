#!/usr/bin/env bash
# Store Obsevia Azure OpenAI creds in homelab Vault for Grok / agents (KV v2: secret/grokbot/azure).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$HOME/launchpad/.env}"
K8S_NS="${K8S_NS:-obsevia-api-staging}"
K8S_SECRET="${K8S_SECRET:-obsevia-chat-backend-secrets}"
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

json="$(kubectl -n "$K8S_NS" get secret "$K8S_SECRET" -o json)"
python3 - "$json" "$VAULT_PATH" "$K8S_NS/$K8S_SECRET" <<'PY'
import base64, json, subprocess, sys

raw, path, src = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.loads(raw)["data"]
keys = [
    "AZURE_GPT_4_1_MINI_ENDPOINT",
    "AZURE_GPT_4_1_MINI_KEY",
    "AZURE_GPT_4_1_MINI_VERSION",
    "AZURE_GPT_4_1_MINI_DEPLOYMENT",
]
args = ["vault", "kv", "put", path]
for k in keys:
    args.append(f"{k}={base64.b64decode(data[k]).decode()}")
args.append("LLM_PROVIDER=azure")
args.append(
    "NOTES=Azure OpenAI for Obsevia/chat + cross-project Grok (from k8s "
    + src
    + ")"
)
subprocess.run(args, check=True)
print(f"OK: {path}")
PY
