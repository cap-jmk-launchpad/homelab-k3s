#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/vault-env.sh
source "$ROOT/scripts/lib/vault-env.sh"
load_vault_env "$ROOT"
: "${VAULT_ADDR:?Set VAULT_ADDR in launchpad/.env}"
SRC="$ROOT/k8s/vault/external-secrets/cluster-secret-store.example.yaml"
OUT="$ROOT/k8s/vault/external-secrets/cluster-secret-store.yaml"
cp "$SRC" "$OUT"
sed -i "s|https://YOUR-CLUSTER.vault.xxxxx.hashicorp.cloud:8200|${VAULT_ADDR}|g" "$OUT"
echo "==> Wrote ${OUT}"
