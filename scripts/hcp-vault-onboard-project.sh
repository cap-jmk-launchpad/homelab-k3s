#!/usr/bin/env bash
# Onboard a SaaS project: Vault policy + ExternalSecret manifest.
#
# Usage:
#   ./scripts/hcp-vault-onboard-project.sh <project> <env> <k8s-namespace>
#
# Examples:
#   ./scripts/hcp-vault-onboard-project.sh agent-swarm staging agent-swarm
#   ./scripts/hcp-vault-onboard-project.sh majico staging majico-staging
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/vault-env.sh
source "$ROOT/scripts/lib/vault-env.sh"
load_vault_env "$ROOT"

PROJECT="${1:-}"
ENV="${2:-}"
NAMESPACE="${3:-}"

if [[ -z "$PROJECT" || -z "$ENV" || -z "$NAMESPACE" ]]; then
  echo "Usage: $0 <project> <env> <k8s-namespace>" >&2
  exit 1
fi

case "$ENV" in
  dev|staging|prod) ;;
  *) echo "ERROR: env must be dev, staging, or prod" >&2; exit 1 ;;
esac

POLICY_NAME="saas-${PROJECT}-${ENV}"
POLICY_FILE="$(mktemp)"
sed -e "s/PROJECT/${PROJECT}/g" -e "s/ENV/${ENV}/g" \
  "$ROOT/k8s/vault/policies/saas-project-env.hcl.tpl" >"$POLICY_FILE"

if [[ -n "${VAULT_TOKEN:-}" && -n "${VAULT_ADDR:-}" ]]; then
  export VAULT_NAMESPACE="${VAULT_NAMESPACE:-admin}"
  echo "==> Writing Vault policy ${POLICY_NAME}"
  vault policy write "$POLICY_NAME" "$POLICY_FILE"
else
  echo "==> Skipping Vault policy write (set VAULT_ADDR + VAULT_TOKEN to apply)"
fi
rm -f "$POLICY_FILE"

# Use project dir keyed by k8s namespace (matches majico-staging layout)
OUT_DIR="$ROOT/k8s/vault/projects/${NAMESPACE}"
mkdir -p "$OUT_DIR"

EXAMPLE="$OUT_DIR/external-secret.example.yaml"
if [[ -f "$EXAMPLE" ]]; then
  cp "$EXAMPLE" "$OUT_DIR/external-secret.yaml"
  echo "==> Copied ${EXAMPLE} → external-secret.yaml"
else
  cat >"$OUT_DIR/external-secret.yaml" <<EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: ${PROJECT}-secrets
  namespace: ${NAMESPACE}
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: hcp-vault
    kind: ClusterSecretStore
  target:
    name: ${PROJECT}-secrets
    creationPolicy: Owner
  dataFrom:
    - extract:
        key: saas/${PROJECT}/${ENV}
EOF
  cp "$OUT_DIR/external-secret.yaml" "$OUT_DIR/external-secret.example.yaml"
  echo "==> Generated ${OUT_DIR}/external-secret.yaml (and .example.yaml)"
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Next steps:"
echo "  1. Seed Vault: ENV_FILE=/path/.env ./scripts/hcp-vault-seed-project.sh ${PROJECT} ${ENV}"
echo "  2. kubectl apply -f ${OUT_DIR}/external-secret.yaml"
echo "  3. Point deployments at secret name in ExternalSecret target"
echo ""
echo "Vault path: secret/saas/${PROJECT}/${ENV}"
