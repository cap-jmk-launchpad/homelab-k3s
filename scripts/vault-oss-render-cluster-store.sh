#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/k8s/vault/external-secrets/cluster-secret-store.example.yaml"
OUT="$ROOT/k8s/vault/external-secrets/cluster-secret-store.yaml"
VAULT_SERVER="${VAULT_ESO_SERVER:-http://vault.vault.svc:8200}"

cp "$SRC" "$OUT"
if [[ "$(uname -s)" == Darwin* ]]; then
  sed -i '' "s|http://vault.vault.svc:8200|${VAULT_SERVER}|g" "$OUT"
else
  sed -i "s|http://vault.vault.svc:8200|${VAULT_SERVER}|g" "$OUT"
fi
echo "==> Wrote ${OUT} (server=${VAULT_SERVER})"
