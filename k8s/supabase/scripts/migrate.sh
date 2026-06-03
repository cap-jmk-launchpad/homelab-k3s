#!/bin/sh
set -eu
export PGHOST="${PGHOST:-db}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGDATABASE="${PGDATABASE:-postgres}"

echo "==> sync supabase role passwords"
export PGPASSWORD="${POSTGRES_PASSWORD}"
for role in authenticator supabase_auth_admin supabase_admin supabase_storage_admin pgbouncer; do
  psql -h "${PGHOST}" -U supabase_admin -d postgres -v ON_ERROR_STOP=1 \
    -c "ALTER USER ${role} WITH PASSWORD '${POSTGRES_PASSWORD}';"
done

echo "==> ensure _supabase database for analytics"
if [ "$(psql -At -c "SELECT 1 FROM pg_database WHERE datname = '_supabase';" || true)" != "1" ]; then
  psql -v ON_ERROR_STOP=1 -c "CREATE DATABASE _supabase"
fi

psql -v ON_ERROR_STOP=1 <<'EOSQL'
CREATE TABLE IF NOT EXISTS public.schema_migrations (
  name text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);
EOSQL

for f in $(ls -1 /migrations/*.sql 2>/dev/null | sort); do
  name="$(basename "$f")"
  applied="$(psql -At -c "SELECT 1 FROM public.schema_migrations WHERE name = '${name}' LIMIT 1;" || true)"
  if [ "$applied" = "1" ]; then
    echo "skip $name"
    continue
  fi
  echo "apply $name"
  psql -v ON_ERROR_STOP=1 -f "$f"
  psql -v ON_ERROR_STOP=1 -c "INSERT INTO public.schema_migrations (name) VALUES ('${name}');"
done

echo "migrate complete"
