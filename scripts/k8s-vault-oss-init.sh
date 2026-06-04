#!/usr/bin/env bash
# Initialize Vault OSS once (Raft PVC), enable KV v2, unseal, merge keys into launchpad/.env.
#
# Usage:
#   ./scripts/k8s-vault-oss-init.sh
#
# VAULT_REGENERATE=1  — destructive: delete PVC + re-init (homelab only)
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/vault-env.sh
source "$ROOT/scripts/lib/vault-env.sh"
load_vault_env "$ROOT"

VAULT_NAMESPACE_K8S="${VAULT_NAMESPACE_K8S:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"
VAULT_IN_CLUSTER="${VAULT_IN_CLUSTER_ADDR:-http://vault.vault.svc:8200}"
VAULT_PUBLIC="${VAULT_PUBLIC_ADDR:-https://vault.klaut.pro}"

command -v kubectl >/dev/null || { echo "ERROR: kubectl required" >&2; exit 1; }
command -v vault >/dev/null || { echo "ERROR: vault CLI required" >&2; exit 1; }

wait_vault_pod() {
  kubectl -n "$VAULT_NAMESPACE_K8S" wait --for=jsonpath='{.status.phase}'=Running pod/"$VAULT_POD" --timeout=180s
}

vault_exec() {
  kubectl -n "$VAULT_NAMESPACE_K8S" exec "$VAULT_POD" -c vault -- "$@"
}

is_initialized() {
  vault_exec vault status -format=json 2>/dev/null | grep -q '"initialized":true' || return 1
}

pvc_has_data() {
  vault_exec test -f /vault/data/vault.db 2>/dev/null
}

if [[ "${VAULT_REGENERATE:-0}" == 1 ]]; then
  echo "WARNING: VAULT_REGENERATE=1 deletes Vault PVC and all secrets in this cluster." >&2
  if [[ "${VAULT_REGENERATE_CONFIRM:-}" != REGENERATE ]]; then
    read -r -p "Type REGENERATE to continue: " confirm
    [[ "$confirm" == REGENERATE ]] || { echo "Aborted." >&2; exit 1; }
  fi
  kubectl -n "$VAULT_NAMESPACE_K8S" delete statefulset vault --ignore-not-found --wait=true
  kubectl -n "$VAULT_NAMESPACE_K8S" delete pvc vault-data --ignore-not-found --wait=true
  kubectl -n "$VAULT_NAMESPACE_K8S" delete secret vault-unseal --ignore-not-found
fi

wait_vault_pod

if ! kubectl -n "$VAULT_NAMESPACE_K8S" get svc vault >/dev/null 2>&1; then
  echo "ERROR: service vault not found — run k8s-vault-oss-apply.sh first" >&2
  exit 1
fi

PF_PID=""
cleanup() {
  [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null || true
}
trap cleanup EXIT

kubectl -n "$VAULT_NAMESPACE_K8S" port-forward "pod/${VAULT_POD}" 18200:8200 >/dev/null 2>&1 &
PF_PID=$!
sleep 2
export VAULT_ADDR="http://127.0.0.1:18200"

need_init=0
if ! is_initialized; then
  need_init=1
elif [[ "${VAULT_REGENERATE:-0}" == 1 ]]; then
  need_init=1
elif ! pvc_has_data; then
  need_init=1
fi

if [[ "$need_init" -eq 1 ]]; then
  echo "==> Initializing Vault (single unseal key for homelab)"
  init_out="$(vault operator init -key-shares=1 -key-threshold=1 -format=json)"
  read -r unseal_key root_token < <(
    python3 -c "import json,sys; d=json.load(sys.stdin); print(d['unseal_keys_b64'][0], d['root_token'])" <<<"$init_out"
  )
  if [[ -z "$unseal_key" || -z "$root_token" ]]; then
    echo "ERROR: could not parse vault operator init output" >&2
    exit 1
  fi
  export VAULT_UNSEAL_KEY="$unseal_key"
  export VAULT_ROOT_TOKEN="$root_token"
  export VAULT_TOKEN="$root_token"

  vault_env_upsert "$LAUNCHPAD_ENV" VAULT_ADDR "$VAULT_PUBLIC" 1 || true
  vault_env_upsert "$LAUNCHPAD_ENV" VAULT_UNSEAL_KEY "$unseal_key" 1
  vault_env_upsert "$LAUNCHPAD_ENV" VAULT_ROOT_TOKEN "$root_token" 1
  vault_env_upsert "$LAUNCHPAD_ENV" VAULT_TOKEN "$root_token" 1
  echo "==> Wrote VAULT_* to ${LAUNCHPAD_ENV} (not committed)"
else
  : "${VAULT_UNSEAL_KEY:?Set VAULT_UNSEAL_KEY in ${LAUNCHPAD_ENV}}"
  : "${VAULT_ROOT_TOKEN:?Set VAULT_ROOT_TOKEN in ${LAUNCHPAD_ENV}}"
  export VAULT_TOKEN="${VAULT_TOKEN:-$VAULT_ROOT_TOKEN}"
  echo "==> Vault already initialized on PVC — reusing keys from .env"
fi

echo "==> Unsealing"
vault operator unseal "$VAULT_UNSEAL_KEY" >/dev/null

export VAULT_TOKEN="${VAULT_TOKEN:-$VAULT_ROOT_TOKEN}"
echo "==> Enabling KV v2 at secret/"
vault secrets enable -version=2 -path=secret kv 2>/dev/null || true

bash "$ROOT/scripts/k8s-vault-oss-secret.sh"

kubectl -n "$VAULT_NAMESPACE_K8S" apply -k "$ROOT/k8s/vault/server/"
kubectl -n "$VAULT_NAMESPACE_K8S" rollout status statefulset/vault --timeout=180s 2>/dev/null || \
  kubectl -n "$VAULT_NAMESPACE_K8S" wait --for=jsonpath='{.status.phase}'=Running pod/"$VAULT_POD" --timeout=180s

vault operator unseal "$VAULT_UNSEAL_KEY" >/dev/null
vault status
echo "==> Vault OSS ready. Rotate VAULT_ROOT_TOKEN after bootstrap; keep VAULT_UNSEAL_KEY for restarts."
