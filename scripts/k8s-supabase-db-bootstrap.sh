#!/usr/bin/env bash
# One-shot: align supabase/postgres role passwords with supabase-secrets (TCP/scram).
set -euo pipefail
NS="${SUPABASE_NAMESPACE:-supabase}"
PG="$(kubectl get secret supabase-secrets -n "$NS" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"
run_sql() {
  kubectl exec -n "$NS" db-0 -- env PGPASSWORD="$PG" psql -h 127.0.0.1 -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -c "$1"
}
for role in authenticator supabase_auth_admin supabase_admin supabase_storage_admin pgbouncer; do
  run_sql "ALTER USER ${role} WITH PASSWORD '${PG}';"
done
echo "==> role passwords synced"
