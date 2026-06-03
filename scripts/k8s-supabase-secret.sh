#!/usr/bin/env bash
# Create supabase-secrets from launchpad .env (reuse unless SUPABASE_REGENERATE_SECRETS=1).
#
# Usage:
#   LAUNCHPAD_ENV=../.env ./scripts/k8s-supabase-secret.sh
#   SUPABASE_REGENERATE_SECRETS=1 ./scripts/k8s-supabase-secret.sh
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

require_cmd kubectl
require_cmd openssl

emit_supabase_keys() {
  if command -v node >/dev/null 2>&1; then
    POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
      JWT_SECRET="$JWT_SECRET" \
      SUPABASE_PUBLIC_URL="$SUPABASE_PUBLIC_URL" \
      SUPABASE_DB_HOST="$SUPABASE_DB_HOST" \
      SUPABASE_DB_PORT="$SUPABASE_DB_PORT" \
      SUPABASE_NAMESPACE="$SUPABASE_NAMESPACE" \
      node "$ROOT/scripts/lib/k8s-supabase-keys.mjs"
    return
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: need node or python3 to derive Supabase JWT keys" >&2
    exit 1
  fi
  POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    JWT_SECRET="$JWT_SECRET" \
    SUPABASE_PUBLIC_URL="$SUPABASE_PUBLIC_URL" \
    SUPABASE_DB_HOST="$SUPABASE_DB_HOST" \
    SUPABASE_DB_PORT="$SUPABASE_DB_PORT" \
    SUPABASE_NAMESPACE="$SUPABASE_NAMESPACE" \
    python3 - <<'PY'
import base64, hashlib, hmac, json, os

def b64url(obj):
    return base64.urlsafe_b64encode(json.dumps(obj, separators=(",", ":")).encode()).decode().rstrip("=")

def sign(role, secret, exp=1983812996):
    header = b64url({"alg": "HS256", "typ": "JWT"})
    payload = b64url({"iss": "supabase-demo", "role": role, "exp": exp})
    sig = base64.urlsafe_b64encode(
        hmac.new(secret.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest()
    ).decode().rstrip("=")
    return f"{header}.{payload}.{sig}"

secret = os.environ.get("JWT_SECRET", "")
pg = os.environ.get("POSTGRES_PASSWORD", "")
host = os.environ.get("SUPABASE_DB_HOST", "db")
port = os.environ.get("SUPABASE_DB_PORT", "5432")
api = os.environ.get("SUPABASE_PUBLIC_URL", "http://127.0.0.1:30480")
ns = os.environ.get("SUPABASE_NAMESPACE", "supabase")
anon = sign("anon", secret)
service = sign("service_role", secret)
db_url = f"postgresql://postgres:{pg}@{host}:{port}/postgres"
print(f"SUPABASE_NAMESPACE={ns}")
print(f"SUPABASE_PUBLIC_URL={api}")
print(f"SUPABASE_URL={api}")
print(f"API_EXTERNAL_URL={api}")
print(f"SITE_URL={api}")
print(f"POSTGRES_HOST={host}")
print(f"POSTGRES_PORT={port}")
print("POSTGRES_DB=postgres")
print(f"JWT_SECRET={secret}")
print(f"ANON_KEY={anon}")
print(f"SERVICE_ROLE_KEY={service}")
print(f"SUPABASE_ANON_KEY={anon}")
print(f"SUPABASE_SERVICE_ROLE_KEY={service}")
print(f"SUPABASE_DB_URL={db_url}")
print(f"DATABASE_URL={db_url}")
print(f"GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin:{pg}@{host}:{port}/postgres")
print(f"PGRST_DB_URI=postgres://authenticator:{pg}@{host}:{port}/postgres")
print(f"POSTGRES_BACKEND_URL=postgresql://supabase_admin:{pg}@{host}:{port}/_supabase")
print("KONG_NODEPORT=30480")
PY
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

load_launchpad_env

regen="${SUPABASE_REGENERATE_SECRETS:-0}"
reuse=0
if [[ "$regen" != "1" && -n "${POSTGRES_PASSWORD:-}" && -n "${JWT_SECRET:-}" ]]; then
  reuse=1
fi

if [[ "$reuse" -eq 0 ]]; then
  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(rand_hex 16)}"
  JWT_SECRET="${JWT_SECRET:-super-secret-jwt-token-with-at-least-32-characters-long-$(rand_hex 8)}"
  DASHBOARD_USERNAME="${DASHBOARD_USERNAME:-supabase}"
  DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-$(rand_hex 12)}"
  SECRET_KEY_BASE="${SECRET_KEY_BASE:-$(rand_hex 32)}"
  PG_META_CRYPTO_KEY="${PG_META_CRYPTO_KEY:-$(rand_hex 16)}"
  VAULT_ENC_KEY="${VAULT_ENC_KEY:-$(rand_hex 16)}"
  LOGFLARE_PUBLIC_ACCESS_TOKEN="${LOGFLARE_PUBLIC_ACCESS_TOKEN:-$(rand_hex 24)}"
  LOGFLARE_PRIVATE_ACCESS_TOKEN="${LOGFLARE_PRIVATE_ACCESS_TOKEN:-$(rand_hex 24)}"
fi

SUPABASE_PUBLIC_URL="${SUPABASE_PUBLIC_URL:-http://127.0.0.1:30480}"
SUPABASE_DB_HOST="${SUPABASE_DB_HOST:-db}"
SUPABASE_DB_PORT="${SUPABASE_DB_PORT:-5432}"
SUPABASE_NAMESPACE="${SUPABASE_NAMESPACE:-supabase}"

eval "$(emit_supabase_keys)"

GOTRUE_DB_DATABASE_URL="${GOTRUE_DB_DATABASE_URL:-postgres://supabase_auth_admin:${POSTGRES_PASSWORD}@${SUPABASE_DB_HOST}:${SUPABASE_DB_PORT}/postgres}"
PGRST_DB_URI="${PGRST_DB_URI:-postgres://authenticator:${POSTGRES_PASSWORD}@${SUPABASE_DB_HOST}:${SUPABASE_DB_PORT}/postgres}"
POSTGRES_BACKEND_URL="${POSTGRES_BACKEND_URL:-postgresql://supabase_admin:${POSTGRES_PASSWORD}@${SUPABASE_DB_HOST}:${SUPABASE_DB_PORT}/_supabase}"

for kv in \
  "SUPABASE_NAMESPACE=$SUPABASE_NAMESPACE" \
  "SUPABASE_PUBLIC_URL=$SUPABASE_PUBLIC_URL" \
  "SUPABASE_URL=$SUPABASE_URL" \
  "API_EXTERNAL_URL=$API_EXTERNAL_URL" \
  "SITE_URL=$SITE_URL" \
  "POSTGRES_HOST=$POSTGRES_HOST" \
  "POSTGRES_PORT=$POSTGRES_PORT" \
  "POSTGRES_DB=$POSTGRES_DB" \
  "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" \
  "JWT_SECRET=$JWT_SECRET" \
  "ANON_KEY=$ANON_KEY" \
  "SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY" \
  "SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY" \
  "SUPABASE_SERVICE_ROLE_KEY=$SUPABASE_SERVICE_ROLE_KEY" \
  "SUPABASE_DB_URL=$SUPABASE_DB_URL" \
  "DATABASE_URL=$DATABASE_URL" \
  "GOTRUE_DB_DATABASE_URL=$GOTRUE_DB_DATABASE_URL" \
  "PGRST_DB_URI=$PGRST_DB_URI" \
  "POSTGRES_BACKEND_URL=$POSTGRES_BACKEND_URL" \
  "DASHBOARD_USERNAME=${DASHBOARD_USERNAME:-supabase}" \
  "DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD:-}" \
  "SECRET_KEY_BASE=${SECRET_KEY_BASE:-}" \
  "PG_META_CRYPTO_KEY=${PG_META_CRYPTO_KEY:-}" \
  "VAULT_ENC_KEY=${VAULT_ENC_KEY:-}" \
  "LOGFLARE_PUBLIC_ACCESS_TOKEN=${LOGFLARE_PUBLIC_ACCESS_TOKEN:-}" \
  "LOGFLARE_PRIVATE_ACCESS_TOKEN=${LOGFLARE_PRIVATE_ACCESS_TOKEN:-}" \
  "KONG_NODEPORT=${KONG_NODEPORT:-30480}"; do
  key="${kv%%=*}"
  val="${kv#*=}"
  [[ -n "$val" ]] && set_env_key "$LAUNCHPAD_ENV" "$key" "$val"
done

kubectl create namespace supabase --dry-run=client -o yaml | kubectl apply -f -
kubectl -n supabase delete secret supabase-secrets --ignore-not-found
kubectl -n supabase create secret generic supabase-secrets \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=ANON_KEY="$ANON_KEY" \
  --from-literal=SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
  --from-literal=DASHBOARD_USERNAME="${DASHBOARD_USERNAME:-supabase}" \
  --from-literal=DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-}" \
  --from-literal=SECRET_KEY_BASE="${SECRET_KEY_BASE:-}" \
  --from-literal=PG_META_CRYPTO_KEY="${PG_META_CRYPTO_KEY:-}" \
  --from-literal=VAULT_ENC_KEY="${VAULT_ENC_KEY:-}" \
  --from-literal=LOGFLARE_PUBLIC_ACCESS_TOKEN="${LOGFLARE_PUBLIC_ACCESS_TOKEN:-}" \
  --from-literal=LOGFLARE_PRIVATE_ACCESS_TOKEN="${LOGFLARE_PRIVATE_ACCESS_TOKEN:-}" \
  --from-literal=GOTRUE_DB_DATABASE_URL="$GOTRUE_DB_DATABASE_URL" \
  --from-literal=PGRST_DB_URI="$PGRST_DB_URI" \
  --from-literal=POSTGRES_BACKEND_URL="$POSTGRES_BACKEND_URL"

echo "==> supabase-secrets updated (namespace supabase)"
echo "    launchpad env: $LAUNCHPAD_ENV"
if [[ "$reuse" -eq 1 ]]; then
  echo "    reused credentials from .env"
else
  echo "    generated new credentials (merged into .env)"
fi
