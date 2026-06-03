#!/usr/bin/env bash
# Create dependency-track-secrets from launchpad .env (reuse unless DEPTRACK_REGENERATE_SECRETS=1).
#
# Usage:
#   LAUNCHPAD_ENV=../.env ./scripts/k8s-dependency-track-secret.sh
#   DEPTRACK_REGENERATE_SECRETS=1 ./scripts/k8s-dependency-track-secret.sh
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

rand_hex() {
  openssl rand -hex "${1:-16}"
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
    printf '%s=%s\n' "$key" "$value" >>"$file"
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

regen="${DEPTRACK_REGENERATE_SECRETS:-0}"
reuse=0
if [[ "$regen" != "1" && -n "${DEPTRACK_POSTGRES_PASSWORD:-}" && -n "${DEPTRACK_ALPINE_SECRET_KEY:-}" ]]; then
  reuse=1
fi

DEPTRACK_NAMESPACE="${DEPTRACK_NAMESPACE:-dependency-track}"
DEPTRACK_NODEPORT="${DEPTRACK_NODEPORT:-30482}"
DEPTRACK_PUBLIC_URL="${DEPTRACK_PUBLIC_URL:-}"
DEPTRACK_MIRROR_CADENCE_HOURS="${DEPTRACK_MIRROR_CADENCE_HOURS:-1}"

if [[ "$reuse" -eq 0 ]]; then
  DEPTRACK_POSTGRES_PASSWORD="${DEPTRACK_POSTGRES_PASSWORD:-$(rand_hex 16)}"
  DEPTRACK_ALPINE_SECRET_KEY="${DEPTRACK_ALPINE_SECRET_KEY:-$(rand_hex 24)}"
fi

TMP_KEY="$(mktemp)"
printf '%s' "$DEPTRACK_ALPINE_SECRET_KEY" >"$TMP_KEY"

for kv in \
  "DEPTRACK_NAMESPACE=$DEPTRACK_NAMESPACE" \
  "DEPTRACK_NODEPORT=$DEPTRACK_NODEPORT" \
  "DEPTRACK_PUBLIC_URL=$DEPTRACK_PUBLIC_URL" \
  "DEPTRACK_MIRROR_CADENCE_HOURS=$DEPTRACK_MIRROR_CADENCE_HOURS" \
  "DEPTRACK_POSTGRES_PASSWORD=$DEPTRACK_POSTGRES_PASSWORD" \
  "DEPTRACK_ALPINE_SECRET_KEY=$DEPTRACK_ALPINE_SECRET_KEY"; do
  key="${kv%%=*}"
  val="${kv#*=}"
  [[ -n "$val" ]] && set_env_key "$LAUNCHPAD_ENV" "$key" "$val"
done

kubectl apply -f "$ROOT/k8s/dependency-track/namespace.yaml"
kubectl -n "$DEPTRACK_NAMESPACE" delete secret dependency-track-secrets --ignore-not-found
kubectl -n "$DEPTRACK_NAMESPACE" create secret generic dependency-track-secrets \
  --from-literal=POSTGRES_PASSWORD="$DEPTRACK_POSTGRES_PASSWORD" \
  --from-file=secret.key="$TMP_KEY"

rm -f "$TMP_KEY"

echo "==> dependency-track-secrets updated (namespace $DEPTRACK_NAMESPACE)"
echo "    launchpad env: $LAUNCHPAD_ENV"
if [[ "$reuse" -eq 1 ]]; then
  echo "    reused credentials from .env"
else
  echo "    generated new credentials (merged into .env)"
fi
echo "    First UI login: admin / admin (change password on first login)"
echo "    NodePort:       http://<blackpearl-ip>:${DEPTRACK_NODEPORT}/"
