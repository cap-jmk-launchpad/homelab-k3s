#!/usr/bin/env bash
# Persist CWE mirror settings in launchpad .env; optional API token secret for edge/WAN.
#
# Usage:
#   LAUNCHPAD_ENV=../.env ./scripts/k8s-cwe-secret.sh
#   CWE_REGENERATE_SECRETS=1 ./scripts/k8s-cwe-secret.sh
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

regen="${CWE_REGENERATE_SECRETS:-0}"
reuse=0
if [[ "$regen" != "1" && -n "${CWE_MIRROR_API_TOKEN:-}" ]]; then
  reuse=1
fi

CWE_NAMESPACE="${CWE_NAMESPACE:-cwe}"
CWE_NODEPORT="${CWE_NODEPORT:-30483}"
CWE_PUBLIC_URL="${CWE_PUBLIC_URL:-}"
CWE_SOURCE_URL="${CWE_SOURCE_URL:-https://cwe.mitre.org/data/xml/cwec_latest.xml.zip}"
CWE_SYNC_SCHEDULE="${CWE_SYNC_SCHEDULE:-*/10 * * * *}"

if [[ "$reuse" -eq 0 ]]; then
  CWE_MIRROR_API_TOKEN="${CWE_MIRROR_API_TOKEN:-$(rand_hex 24)}"
fi

for kv in \
  "CWE_NAMESPACE=$CWE_NAMESPACE" \
  "CWE_NODEPORT=$CWE_NODEPORT" \
  "CWE_PUBLIC_URL=$CWE_PUBLIC_URL" \
  "CWE_SOURCE_URL=$CWE_SOURCE_URL" \
  "CWE_SYNC_SCHEDULE=$CWE_SYNC_SCHEDULE" \
  "CWE_MIRROR_API_TOKEN=$CWE_MIRROR_API_TOKEN"; do
  key="${kv%%=*}"
  val="${kv#*=}"
  [[ -n "$val" ]] && set_env_key "$LAUNCHPAD_ENV" "$key" "$val"
done

kubectl apply -f "$ROOT/k8s/cwe/namespace.yaml"
kubectl -n "$CWE_NAMESPACE" delete secret cwe-mirror-secrets --ignore-not-found
kubectl -n "$CWE_NAMESPACE" create secret generic cwe-mirror-secrets \
  --from-literal=CWE_MIRROR_API_TOKEN="$CWE_MIRROR_API_TOKEN"

echo "==> cwe-mirror-secrets updated (namespace $CWE_NAMESPACE)"
echo "    launchpad env: $LAUNCHPAD_ENV"
if [[ "$reuse" -eq 1 ]]; then
  echo "    reused CWE_MIRROR_API_TOKEN from .env"
else
  echo "    generated CWE_MIRROR_API_TOKEN (merged into .env)"
fi
echo "    NodePort: http://<blackpearl-ip>:${CWE_NODEPORT}/manifest.json"
