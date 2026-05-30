#!/usr/bin/env bash
# Create agent-swarm-secrets (app keys + Supabase JWT derived from db secret).
#
# Usage:
#   ./scripts/k8s-agent-swarm-secret.sh [/path/to/li-cursor-agents/.env]
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-}"
AGENTS_DIR=""
if [[ -n "$ENV_FILE" ]]; then
  AGENTS_DIR="$(cd "$(dirname "$ENV_FILE")" && pwd)"
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: missing $ENV_FILE" >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  if [[ -f "$AGENTS_DIR/.env.supabase" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$AGENTS_DIR/.env.supabase"
    set +a
  fi
fi

if ! kubectl get secret agent-swarm-db-secrets -n agent-swarm >/dev/null 2>&1; then
  echo "==> creating db secret first"
  "$ROOT/scripts/k8s-agent-swarm-db-secret.sh"
fi

JWT_SECRET="$(kubectl get secret agent-swarm-db-secrets -n agent-swarm -o jsonpath='{.data.JWT_SECRET}' | base64 -d)"
POSTGRES_PASSWORD="$(kubectl get secret agent-swarm-db-secrets -n agent-swarm -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"

_keys="$(
  JWT_SECRET="$JWT_SECRET" POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    SUPABASE_URL="http://postgrest:54321" SUPABASE_DB_HOST="postgres" \
    node "$ROOT/scripts/lib/k8s-supabase-keys.mjs"
)"

kubectl create namespace agent-swarm --dry-run=client -o yaml | kubectl apply -f -

args=()
[[ -n "${CURSOR_API_KEY:-}" ]] && args+=(--from-literal=CURSOR_API_KEY="$CURSOR_API_KEY")
[[ -n "${GH_TOKEN:-}" ]] && args+=(--from-literal=GH_TOKEN="$GH_TOKEN")

while IFS= read -r line; do
  key="${line%%=*}"
  val="${line#*=}"
  args+=(--from-literal="$key=$val")
done <<< "$_keys"

if [[ ${#args[@]} -lt 3 ]]; then
  echo "ERROR: need CURSOR_API_KEY in .env and db secret for Supabase keys" >&2
  exit 1
fi

kubectl -n agent-swarm delete secret agent-swarm-secrets --ignore-not-found
kubectl -n agent-swarm create secret generic agent-swarm-secrets "${args[@]}"
echo "==> secret agent-swarm-secrets updated in namespace agent-swarm"
