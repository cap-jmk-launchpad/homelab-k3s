#!/usr/bin/env bash
# Create in-cluster vault-unseal secret from launchpad/.env (never commit keys).
#
# Usage:
#   ./scripts/k8s-vault-oss-secret.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/vault-env.sh
source "$ROOT/scripts/lib/vault-env.sh"
load_vault_env "$ROOT"

VAULT_NAMESPACE_K8S="${VAULT_NAMESPACE_K8S:-vault}"
: "${VAULT_UNSEAL_KEY:?Set VAULT_UNSEAL_KEY in launchpad/.env (from k8s-vault-oss-init.sh)}"

kubectl create namespace "$VAULT_NAMESPACE_K8S" --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$VAULT_NAMESPACE_K8S" create secret generic vault-unseal \
  --from-literal=key="$VAULT_UNSEAL_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> vault-unseal secret applied in namespace ${VAULT_NAMESPACE_K8S}"
