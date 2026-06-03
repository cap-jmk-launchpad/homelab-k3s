#!/usr/bin/env bash
# Bootstrap Dependency-Track admin password + Automation API key; merge into launchpad .env.
#
# Usage (on blackpearl or host with kubectl + cluster DNS / port-forward):
#   LAUNCHPAD_ENV=~/launchpad/.env ./scripts/k8s-dependency-track-bootstrap-auth.sh
#   DEPTRACK_REGENERATE_API_KEY=1  # force new API key
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

# shellcheck source=lib/load-launchpad-deptrack-env.sh
source "$ROOT/scripts/lib/load-launchpad-deptrack-env.sh"

api_curl() {
  kubectl -n "$DEPTRACK_NAMESPACE" exec "$API_POD" -- \
    curl -fsS "$@" "http://127.0.0.1:8080${API_PATH}"
}

login_http_code() {
  local pw="$1"
  kubectl -n "$DEPTRACK_NAMESPACE" exec "$API_POD" -- \
    curl -sS -o /dev/null -w '%{http_code}' \
    -d "username=${DEPTRACK_ADMIN_USER}" \
    -d "password=${pw}" \
    "http://127.0.0.1:8080/api/v1/user/login" 2>/dev/null || echo "000"
}

reset_admin_password_db() {
  local pw="$1"
  require_cmd python3
  local pg_pass hash
  pg_pass="$(kubectl -n "$DEPTRACK_NAMESPACE" get secret dependency-track-secrets -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"
  hash="$(NEW_PASSWORD="$pw" python3 - <<'PY'
from hashlib import sha512
import bcrypt
import os
password = os.environ["NEW_PASSWORD"]
prehash = sha512(password.encode()).hexdigest().encode()
salt = bcrypt.gensalt(rounds=14, prefix=b"2a")
print(bcrypt.hashpw(prehash, salt).decode())
PY
)"
  kubectl -n "$DEPTRACK_NAMESPACE" exec dependency-track-postgres-0 -- \
    env PGPASSWORD="$pg_pass" psql -U dtrack -d dtrack -v ON_ERROR_STOP=1 -c \
    "UPDATE \"MANAGEDUSER\" SET \"PASSWORD\" = '${hash}', \"FORCE_PASSWORD_CHANGE\" = false, \"LAST_PASSWORD_CHANGE\" = NOW() WHERE \"USERNAME\" = '${DEPTRACK_ADMIN_USER}';" >/dev/null
}

require_cmd kubectl
require_cmd openssl
require_cmd jq

load_launchpad_deptrack_env

DEPTRACK_NAMESPACE="${DEPTRACK_NAMESPACE:-dependency-track}"
DEPTRACK_NODEPORT="${DEPTRACK_NODEPORT:-30482}"
DEPTRACK_URL="${DEPTRACK_URL:-http://192.168.10.33:${DEPTRACK_NODEPORT}}"
DEPTRACK_API_BASE_URL="${DEPTRACK_API_BASE_URL:-http://dependency-track-api-server.${DEPTRACK_NAMESPACE}.svc.cluster.local:8080}"
DEPTRACK_ADMIN_USER="${DEPTRACK_ADMIN_USER:-admin}"
DEPTRACK_DEFAULT_PASSWORD="${DEPTRACK_DEFAULT_PASSWORD:-admin}"
DEPTRACK_AUTOMATION_TEAM="${DEPTRACK_AUTOMATION_TEAM:-Automation}"
regen_key="${DEPTRACK_REGENERATE_API_KEY:-0}"

API_POD="$(kubectl -n "$DEPTRACK_NAMESPACE" get pods -l app.kubernetes.io/component=api-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "$API_POD" ]]; then
  API_POD="$(kubectl -n "$DEPTRACK_NAMESPACE" get pods -o name 2>/dev/null | sed -n 's|pod/dependency-track-api-server-0|dependency-track-api-server-0|p' | head -1)"
fi
if [[ -z "$API_POD" ]]; then
  echo "ERROR: no Dependency-Track API pod in namespace $DEPTRACK_NAMESPACE" >&2
  exit 1
fi

kubectl -n "$DEPTRACK_NAMESPACE" get pod "$API_POD" >/dev/null 2>&1 || {
  echo "ERROR: API pod $API_POD not found" >&2
  exit 1
}

admin_password="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"

echo "==> set strong random admin password"
API_PATH="/api/v1/user/forceChangePassword"
rotated=0
for try_pw in "$DEPTRACK_DEFAULT_PASSWORD" "${DEPTRACK_ADMIN_PASSWORD:-}"; do
  [[ -z "$try_pw" || "$try_pw" == "$admin_password" ]] && continue
  code="$(kubectl -n "$DEPTRACK_NAMESPACE" exec "$API_POD" -- \
    curl -sS -o /dev/null -w '%{http_code}' \
    -d "username=${DEPTRACK_ADMIN_USER}" \
    -d "password=${try_pw}" \
    -d "newPassword=${admin_password}" \
    -d "confirmPassword=${admin_password}" \
    "http://127.0.0.1:8080${API_PATH}" 2>/dev/null || echo "000")"
  if [[ "$code" == "200" ]]; then
    echo "    rotated via API (previous password accepted)"
    rotated=1
    break
  fi
done

if [[ "$(login_http_code "$admin_password")" != "200" ]]; then
  if [[ "$rotated" -eq 0 && -n "${DEPTRACK_ADMIN_PASSWORD:-}" && "$(login_http_code "$DEPTRACK_ADMIN_PASSWORD")" == "200" ]]; then
    code="$(kubectl -n "$DEPTRACK_NAMESPACE" exec "$API_POD" -- \
      curl -sS -o /dev/null -w '%{http_code}' \
      -d "username=${DEPTRACK_ADMIN_USER}" \
      -d "password=${DEPTRACK_ADMIN_PASSWORD}" \
      -d "newPassword=${admin_password}" \
      -d "confirmPassword=${admin_password}" \
      "http://127.0.0.1:8080${API_PATH}" 2>/dev/null || echo "000")"
    if [[ "$code" == "200" ]]; then
      echo "    rotated via API from .env password"
      rotated=1
    fi
  fi
fi

if [[ "$(login_http_code "$admin_password")" != "200" ]]; then
  echo "    API rotation unavailable — resetting admin hash in Postgres"
  reset_admin_password_db "$admin_password"
fi

if [[ "$(login_http_code "$admin_password")" != "200" ]]; then
  echo "ERROR: admin login still failing after password bootstrap" >&2
  exit 1
fi

echo "==> login as ${DEPTRACK_ADMIN_USER}"
API_PATH="/api/v1/user/login"
login_body="$(kubectl -n "$DEPTRACK_NAMESPACE" exec "$API_POD" -- \
  curl -fsS \
  -d "username=${DEPTRACK_ADMIN_USER}" \
  -d "password=${admin_password}" \
  "http://127.0.0.1:8080${API_PATH}")"
token="$(echo "$login_body" | jq -r 'if type == "object" then .token // empty else empty end' 2>/dev/null || true)"
if [[ -z "$token" && "$login_body" == eyJ* ]]; then
  token="$login_body"
fi
if [[ -z "$token" ]]; then
  echo "ERROR: login failed — check admin password" >&2
  exit 1
fi

auth_hdr=(-H "Authorization: Bearer ${token}")

echo "==> locate Automation team"
API_PATH="/api/v1/team"
teams_json="$(api_curl "${auth_hdr[@]}")"
team_uuid="$(echo "$teams_json" | jq -r --arg n "$DEPTRACK_AUTOMATION_TEAM" '.[] | select(.name == $n) | .uuid' | head -1)"
if [[ -z "$team_uuid" ]]; then
  echo "ERROR: team '$DEPTRACK_AUTOMATION_TEAM' not found" >&2
  exit 1
fi

has_sys_cfg="$(echo "$teams_json" | jq -r --arg u "$team_uuid" '.[] | select(.uuid == $u) | .permissions[]?.name' | grep -Fx 'SYSTEM_CONFIGURATION' || true)"
if [[ -z "$has_sys_cfg" ]]; then
  echo "==> grant SYSTEM_CONFIGURATION to ${DEPTRACK_AUTOMATION_TEAM}"
  API_PATH="/api/v1/permission/SYSTEM_CONFIGURATION/team/${team_uuid}"
  api_curl -X POST "${auth_hdr[@]}" >/dev/null
fi

api_key="${DEPTRACK_API_KEY:-}"
if [[ -z "$api_key" || "$regen_key" == "1" ]]; then
  echo "==> create Automation API key"
  API_PATH="/api/v1/team/${team_uuid}/key"
  key_json="$(api_curl -X PUT "${auth_hdr[@]}")"
  api_key="$(echo "$key_json" | jq -r '.key // .apiKey // empty')"
  if [[ -z "$api_key" ]]; then
    echo "ERROR: could not parse API key from response" >&2
    exit 1
  fi
else
  echo "==> reuse existing DEPTRACK_API_KEY from env"
fi

echo "==> merge credentials into $LAUNCHPAD_ENV"
for kv in \
  "DEPTRACK_URL=$DEPTRACK_URL" \
  "DEPTRACK_API_BASE_URL=$DEPTRACK_API_BASE_URL" \
  "DEPTRACK_NAMESPACE=$DEPTRACK_NAMESPACE" \
  "DEPTRACK_NODEPORT=$DEPTRACK_NODEPORT" \
  "DEPTRACK_ADMIN_USER=$DEPTRACK_ADMIN_USER" \
  "DEPTRACK_ADMIN_PASSWORD=$admin_password" \
  "DEPTRACK_API_KEY=$api_key"; do
  key="${kv%%=*}"
  val="${kv#*=}"
  [[ -n "$val" ]] && set_env_key "$LAUNCHPAD_ENV" "$key" "$val"
done

echo "==> done"
echo "    UI:      $DEPTRACK_URL"
echo "    API:     $DEPTRACK_API_BASE_URL"
echo "    user:    $DEPTRACK_ADMIN_USER"
echo "    api key: (stored in $LAUNCHPAD_ENV as DEPTRACK_API_KEY)"
