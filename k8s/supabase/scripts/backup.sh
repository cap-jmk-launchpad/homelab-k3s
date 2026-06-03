#!/bin/sh
set -eu
TS="${TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT="/backups/${TS}"
mkdir -p "$OUT"
export PGPASSWORD="${POSTGRES_PASSWORD}"
pg_dump -h db -U postgres -d postgres -Fc -f "${OUT}/postgres.dump"
pg_dump -h db -U postgres -d postgres --schema-only -f "${OUT}/schema.sql"
echo "backup_complete ts=${TS}" > "${OUT}/README.txt"
ls -la "$OUT"
