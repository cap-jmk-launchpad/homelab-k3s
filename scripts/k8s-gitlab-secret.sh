#!/usr/bin/env bash
# Create gitlab-secrets from launchpad .env (reuse unless GITLAB_REGENERATE_SECRETS=1).
#
# Usage:
#   LAUNCHPAD_ENV=../.env ./scripts/k8s-gitlab-secret.sh
#   GITLAB_REGENERATE_SECRETS=1 ./scripts/k8s-gitlab-secret.sh
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

emit_omnibus_rb() {
  local url="$1" token="$2"
  cat <<EOF
external_url '${url}'
gitlab_rails['initial_shared_runners_registration_token'] = '${token}'
gitlab_rails['gitlab_sign_in_enabled'] = true
EOF
}

require_cmd kubectl
require_cmd openssl

load_launchpad_env

regen="${GITLAB_REGENERATE_SECRETS:-0}"
reuse=0
if [[ "$regen" != "1" && -n "${GITLAB_ROOT_PASSWORD:-}" && -n "${GITLAB_RUNNER_REGISTRATION_TOKEN:-}" ]]; then
  reuse=1
fi

GITLAB_NAMESPACE="${GITLAB_NAMESPACE:-gitlab}"
GITLAB_NODEPORT="${GITLAB_NODEPORT:-30481}"
GITLAB_EXTERNAL_URL="${GITLAB_EXTERNAL_URL:-http://127.0.0.1:${GITLAB_NODEPORT}}"
GITLAB_URL="${GITLAB_URL:-http://gitlab.gitlab.svc.cluster.local}"
GITLAB_PUBLIC_URL="${GITLAB_PUBLIC_URL:-}"
GITLAB_REGISTRY_ENABLED="${GITLAB_REGISTRY_ENABLED:-0}"

if [[ "$reuse" -eq 0 ]]; then
  GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD:-$(rand_hex 12)}"
  GITLAB_RUNNER_REGISTRATION_TOKEN="${GITLAB_RUNNER_REGISTRATION_TOKEN:-$(rand_hex 20)}"
fi

OMNIBUS_RB="$(emit_omnibus_rb "$GITLAB_EXTERNAL_URL" "$GITLAB_RUNNER_REGISTRATION_TOKEN")"
TMP_OMNIBUS="$(mktemp)"
printf '%s\n' "$OMNIBUS_RB" >"$TMP_OMNIBUS"

for kv in \
  "GITLAB_NAMESPACE=$GITLAB_NAMESPACE" \
  "GITLAB_NODEPORT=$GITLAB_NODEPORT" \
  "GITLAB_EXTERNAL_URL=$GITLAB_EXTERNAL_URL" \
  "GITLAB_URL=$GITLAB_URL" \
  "GITLAB_PUBLIC_URL=$GITLAB_PUBLIC_URL" \
  "GITLAB_REGISTRY_ENABLED=$GITLAB_REGISTRY_ENABLED" \
  "GITLAB_ROOT_PASSWORD=$GITLAB_ROOT_PASSWORD" \
  "GITLAB_RUNNER_REGISTRATION_TOKEN=$GITLAB_RUNNER_REGISTRATION_TOKEN"; do
  key="${kv%%=*}"
  val="${kv#*=}"
  [[ -n "$val" ]] && set_env_key "$LAUNCHPAD_ENV" "$key" "$val"
done

kubectl create namespace "$GITLAB_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "$GITLAB_NAMESPACE" delete secret gitlab-secrets --ignore-not-found
kubectl -n "$GITLAB_NAMESPACE" create secret generic gitlab-secrets \
  --from-literal=GITLAB_ROOT_PASSWORD="$GITLAB_ROOT_PASSWORD" \
  --from-literal=GITLAB_RUNNER_REGISTRATION_TOKEN="$GITLAB_RUNNER_REGISTRATION_TOKEN" \
  --from-literal=GITLAB_URL="$GITLAB_URL" \
  --from-literal=GITLAB_NAMESPACE="$GITLAB_NAMESPACE" \
  --from-file=omnibus.rb="$TMP_OMNIBUS"

rm -f "$TMP_OMNIBUS"

echo "==> gitlab-secrets updated (namespace $GITLAB_NAMESPACE)"
echo "    launchpad env: $LAUNCHPAD_ENV"
if [[ "$reuse" -eq 1 ]]; then
  echo "    reused credentials from .env"
else
  echo "    generated new credentials (merged into .env)"
fi
echo "    root login: root / (see GITLAB_ROOT_PASSWORD in .env)"
echo "    NodePort:   http://<blackpearl-ip>:${GITLAB_NODEPORT}/"
