#!/bin/sh
# Apply li-cursor-agents SQL migrations once (tracks public.schema_migrations).
set -eu

export PGHOST="${PGHOST:-postgres}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
export PGDATABASE="${PGDATABASE:-postgres}"

echo "==> wait for postgres"
until pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER"; do sleep 2; done

echo "==> supabase-compatible roles"
psql -v ON_ERROR_STOP=1 <<EOSQL
CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
  END IF;
END
\$\$;

DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
    CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD '${AUTHENTICATOR_PASSWORD}';
  ELSE
    ALTER ROLE authenticator WITH LOGIN PASSWORD '${AUTHENTICATOR_PASSWORD}';
  END IF;
END
\$\$;

GRANT anon, authenticated, service_role TO authenticator;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON SCHEMA public TO postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.schema_migrations (
  name text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);
EOSQL

echo "==> apply migrations"
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

echo "==> grants on existing objects"
psql -v ON_ERROR_STOP=1 <<'EOSQL'
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;
EOSQL

echo "==> migrate complete"
