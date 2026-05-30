#!/usr/bin/env bash
# Create agent-swarm-secrets from li-cursor-agents .env (+ .env.supabase if present).
#
# Usage:
#   ./scripts/k8s-agent-swarm-secret.sh [/path/to/li-cursor-agents/.env]
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${1:-}"
if [[ -z "$ENV_FILE" ]]; then
  echo "Usage: $0 /path/to/li-cursor-agents/.env" >&2
  exit 1
fi
AGENTS_DIR="$(cd "$(dirname "$ENV_FILE")" && pwd)"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a
if [[ -f "$AGENTS_DIR/.env.supabase" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$AGENTS_DIR/.env.supabase"
  set +a
fi

kubectl create namespace agent-swarm --dry-run=client -o yaml | kubectl apply -f -

args=()
[[ -n "${CURSOR_API_KEY:-}" ]] && args+=(--from-literal=CURSOR_API_KEY="$CURSOR_API_KEY")
[[ -n "${GH_TOKEN:-}" ]] && args+=(--from-literal=GH_TOKEN="$GH_TOKEN")
[[ -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]] && args+=(--from-literal=SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY")
[[ -n "${SUPABASE_ANON_KEY:-}" ]] && args+=(--from-literal=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
[[ -n "${SUPABASE_DB_URL:-}" ]] && args+=(--from-literal=SUPABASE_DB_URL="$SUPABASE_DB_URL")

if [[ ${#args[@]} -lt 2 ]]; then
  echo "ERROR: need at least CURSOR_API_KEY and Supabase keys in $ENV_FILE / .env.supabase" >&2
  exit 1
fi

kubectl -n agent-swarm delete secret agent-swarm-secrets --ignore-not-found
kubectl -n agent-swarm create secret generic agent-swarm-secrets "${args[@]}"
echo "==> secret agent-swarm-secrets updated in namespace agent-swarm"
