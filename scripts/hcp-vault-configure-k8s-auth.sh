#!/usr/bin/env bash
# Configure HCP Vault Kubernetes auth for External Secrets Operator.
#
# Prerequisites:
#   - vault CLI logged in (VAULT_ADDR, VAULT_NAMESPACE=admin, VAULT_TOKEN in .env)
#   - kubectl context = homelab k3s
#   - ./scripts/hcp-vault-install-eso.sh already run
#
# Usage:
#   ./scripts/hcp-vault-configure-k8s-auth.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/vault-env.sh
source "$ROOT/scripts/lib/vault-env.sh"
load_vault_env "$ROOT"

: "${VAULT_ADDR:?Set VAULT_ADDR in .env (HCP public cluster URL)}"
: "${VAULT_TOKEN:?Set VAULT_TOKEN in .env (admin token from HCP portal, bootstrap only)}"
export VAULT_NAMESPACE="${VAULT_NAMESPACE:-admin}"

VAULT_AUTH_SA="${VAULT_AUTH_SA:-vault-auth}"
VAULT_AUTH_NS="${VAULT_AUTH_NS:-external-secrets}"
K8S_AUTH_ROLE="${K8S_AUTH_ROLE:-external-secrets}"
ESO_SA="${ESO_SA:-external-secrets}"
ESO_NS="${ESO_NS:-external-secrets}"

command -v vault >/dev/null || { echo "ERROR: vault CLI not found" >&2; exit 1; }
command -v kubectl >/dev/null || { echo "ERROR: kubectl not found" >&2; exit 1; }

echo "==> Creating TokenReview service account (${VAULT_AUTH_SA} in ${VAULT_AUTH_NS})"
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${VAULT_AUTH_SA}
  namespace: ${VAULT_AUTH_NS}
---
apiVersion: v1
kind: Secret
metadata:
  name: ${VAULT_AUTH_SA}
  namespace: ${VAULT_AUTH_NS}
  annotations:
    kubernetes.io/service-account.name: ${VAULT_AUTH_SA}
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-tokenreview
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: ${VAULT_AUTH_SA}
    namespace: ${VAULT_AUTH_NS}
EOF

# Wait for token to populate (k3s may take a moment)
for _ in $(seq 1 30); do
  TOKEN_REVIEW_JWT="$(kubectl get secret "${VAULT_AUTH_SA}" -n "${VAULT_AUTH_NS}" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || true)"
  [[ -n "$TOKEN_REVIEW_JWT" ]] && break
  sleep 1
done
[[ -n "$TOKEN_REVIEW_JWT" ]] || { echo "ERROR: vault-auth token not ready" >&2; exit 1; }

KUBE_HOST="${KUBE_HOST:-$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')}"
KUBE_CA="$(mktemp)"
kubectl get secret "${VAULT_AUTH_SA}" -n "${VAULT_AUTH_NS}" -o jsonpath='{.data.ca\.crt}' | base64 -d >"$KUBE_CA"

echo "==> Enabling Kubernetes auth in Vault"
vault auth enable kubernetes 2>/dev/null || true

echo "==> Configuring auth/kubernetes (host=${KUBE_HOST})"
vault write auth/kubernetes/config \
  token_reviewer_jwt="$TOKEN_REVIEW_JWT" \
  kubernetes_host="$KUBE_HOST" \
  kubernetes_ca_cert=@"$KUBE_CA" \
  disable_local_ca_jwt=true
rm -f "$KUBE_CA"

echo "==> Writing policy external-secrets-read"
vault policy write external-secrets-read "$ROOT/k8s/vault/policies/external-secrets-read.hcl"

echo "==> Creating role ${K8S_AUTH_ROLE} for ESO service account"
vault write "auth/kubernetes/role/${K8S_AUTH_ROLE}" \
  bound_service_account_names="$ESO_SA" \
  bound_service_account_namespaces="$ESO_NS" \
  policies=external-secrets-read \
  ttl=1h \
  audience=vault

echo "==> Vault Kubernetes auth configured"
echo "    Next: copy cluster-secret-store.example.yaml → cluster-secret-store.yaml, set VAULT_ADDR, kubectl apply"
