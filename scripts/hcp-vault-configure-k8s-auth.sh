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

: "${VAULT_ADDR:?Set VAULT_ADDR in launchpad/.env}"
: "${VAULT_TOKEN:?Set VAULT_TOKEN or VAULT_ROOT_TOKEN in .env (bootstrap only)}"
if vault_is_hcp; then
  export VAULT_NAMESPACE="${VAULT_NAMESPACE:-admin}"
else
  unset VAULT_NAMESPACE
  export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:30485}"
fi

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

if [[ -n "${KUBE_HOST:-}" ]]; then
  :
elif vault_is_hcp; then
  KUBE_HOST="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
else
  # In-cluster Vault must not use localhost apiserver (127.0.0.1 is the pod, not the node).
  KUBE_HOST="https://kubernetes.default.svc.cluster.local"
fi
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
role_args=(
  bound_service_account_names="$ESO_SA"
  bound_service_account_namespaces="$ESO_NS"
  policies=external-secrets-read
  ttl=1h
)
# audience= requires ESO 0.15+ ClusterSecretStore audiences field (Vault 1.21+)
if [[ -z "${VAULT_K8S_AUTH_AUDIENCE:-}" && ! vault_is_hcp ]]; then
  VAULT_K8S_AUTH_AUDIENCE=k3s
fi
if [[ "${VAULT_K8S_AUTH_AUDIENCE:-}" != "" ]]; then
  role_args+=(audience="${VAULT_K8S_AUTH_AUDIENCE}")
fi
vault write "auth/kubernetes/role/${K8S_AUTH_ROLE}" "${role_args[@]}"

echo "==> Vault Kubernetes auth configured"
echo "    Next: copy cluster-secret-store.example.yaml → cluster-secret-store.yaml, set VAULT_ADDR, kubectl apply"
