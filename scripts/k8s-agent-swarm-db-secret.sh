#!/usr/bin/env bash
# Create agent-swarm-db-secrets (Postgres + PostgREST JWT).
#
# Usage:
#   ./scripts/k8s-agent-swarm-db-secret.sh
#   POSTGRES_PASSWORD=... JWT_SECRET=... ./scripts/k8s-agent-swarm-db-secret.sh
#
set -euo pipefail

POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 16)}"
AUTHENTICATOR_PASSWORD="${AUTHENTICATOR_PASSWORD:-$POSTGRES_PASSWORD}"
JWT_SECRET="${JWT_SECRET:-super-secret-jwt-token-with-at-least-32-characters-long}"
PGRST_DB_URI="postgresql://authenticator:${AUTHENTICATOR_PASSWORD}@postgres:5432/postgres"

kubectl create namespace agent-swarm --dry-run=client -o yaml | kubectl apply -f -

kubectl -n agent-swarm delete secret agent-swarm-db-secrets --ignore-not-found
kubectl -n agent-swarm create secret generic agent-swarm-db-secrets \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=AUTHENTICATOR_PASSWORD="$AUTHENTICATOR_PASSWORD" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=PGRST_DB_URI="$PGRST_DB_URI"

echo "==> agent-swarm-db-secrets created (POSTGRES_PASSWORD not printed — store in password manager)"
