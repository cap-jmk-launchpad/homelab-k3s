#!/usr/bin/env bash
# Persist step-ca passwords in launchpad .env; create Kubernetes secret.
#
# Usage:
#   LAUNCHPAD_ENV=../.env ./scripts/k8s-step-ca-secret.sh
#   STEP_CA_REGENERATE_SECRETS=1 ./scripts/k8s-step-ca-secret.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing $1" >&2
    exit 1
  }
}

rand_pass() {
  openssl rand -base64 32 | tr -d '/+=' | head -c 32
}

set_env_key() {
  local file="$1" key="$2" value="$3"
  touch "$file"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    awk -v k="$key" -v v="$value" '
      BEGIN { done = 0 }
      $0 ~ "^" k "=" { print k "=" v; done = 1; next }
      { print }
      END { if (!done) print k "=" v }
    ' "$file" >"$tmp"
    mv "$tmp" "$file"
  else
    printf '%s=%q\n' "$key" "$value" >>"$file"
  fi
}

load_launchpad_env() {
  [[ -f "$LAUNCHPAD_ENV" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  sed '1s/^\xEF\xBB\xBF//; s/\r$//' "$LAUNCHPAD_ENV" >"$tmp"
  set -a
  # shellcheck disable=SC1090
  source "$tmp"
  set +a
  rm -f "$tmp"
}

require_cmd kubectl
require_cmd openssl

load_launchpad_env

regen="${STEP_CA_REGENERATE_SECRETS:-0}"
reuse=0
if [[ "$regen" != "1" && -n "${STEP_CA_PASSWORD:-}" && -n "${STEP_PROVISIONER_PASSWORD:-}" ]]; then
  reuse=1
fi

STEP_CA_NAMESPACE="${STEP_CA_NAMESPACE:-step-ca}"
STEP_CA_NODEPORT="${STEP_CA_NODEPORT:-30484}"
STEP_CA_DNS="${STEP_CA_DNS:-ca.homelab.lan,pki.homelab.lan}"
STEP_CA_ACME_URL="${STEP_CA_ACME_URL:-https://ca.homelab.lan/acme/acme/directory}"

if [[ "$reuse" -eq 0 ]]; then
  STEP_CA_PASSWORD="${STEP_CA_PASSWORD:-$(rand_pass)}"
  STEP_PROVISIONER_PASSWORD="${STEP_PROVISIONER_PASSWORD:-$(rand_pass)}"
fi

for kv in \
  "STEP_CA_NAMESPACE=$STEP_CA_NAMESPACE" \
  "STEP_CA_NODEPORT=$STEP_CA_NODEPORT" \
  "STEP_CA_DNS=$STEP_CA_DNS" \
  "STEP_CA_ACME_URL=$STEP_CA_ACME_URL" \
  "STEP_CA_PASSWORD=$STEP_CA_PASSWORD" \
  "STEP_PROVISIONER_PASSWORD=$STEP_PROVISIONER_PASSWORD"; do
  key="${kv%%=*}"
  val="${kv#*=}"
  [[ -n "$val" ]] && set_env_key "$LAUNCHPAD_ENV" "$key" "$val"
done

kubectl apply -f "$ROOT/k8s/step-ca/namespace.yaml"
kubectl -n "$STEP_CA_NAMESPACE" delete secret step-ca-secrets --ignore-not-found
kubectl -n "$STEP_CA_NAMESPACE" create secret generic step-ca-secrets \
  --from-literal=STEP_CA_PASSWORD="$STEP_CA_PASSWORD" \
  --from-literal=STEP_PROVISIONER_PASSWORD="$STEP_PROVISIONER_PASSWORD"

echo "==> step-ca-secrets updated (namespace $STEP_CA_NAMESPACE)"
echo "    launchpad env: $LAUNCHPAD_ENV"
if [[ "$reuse" -eq 1 ]]; then
  echo "    reused STEP_CA_* passwords from .env"
else
  echo "    generated STEP_CA_PASSWORD + STEP_PROVISIONER_PASSWORD (merged into .env)"
fi
echo "    NodePort: https://192.168.10.33:${STEP_CA_NODEPORT}/health"
echo "    ACME:     ${STEP_CA_ACME_URL}"
echo ""
echo "    Install root CA after first deploy:"
echo "      kubectl -n ${STEP_CA_NAMESPACE} exec deploy/step-ca -- step ca root > homelab-root-ca.crt"
