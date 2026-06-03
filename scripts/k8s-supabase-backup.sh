#!/usr/bin/env bash
# Trigger an on-demand Supabase Postgres backup into PVC supabase-backups.
#
# Usage:
#   ./scripts/k8s-supabase-backup.sh
#   BACKUP_TS=20260101T120000Z ./scripts/k8s-supabase-restore.sh  # see restore
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS="${SUPABASE_NAMESPACE:-supabase}"
TS="${TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
JOB="supabase-backup-manual-${TS}"

kubectl get secret supabase-secrets -n "$NS" >/dev/null 2>&1 || {
  echo "ERROR: namespace $NS missing supabase-secrets" >&2
  exit 1
}

kubectl -n "$NS" delete job "$JOB" --ignore-not-found
kubectl -n "$NS" create job "$JOB" --from=cronjob/supabase-backup
kubectl -n "$NS" wait --for=condition=complete "job/$JOB" --timeout=900s
kubectl -n "$NS" logs "job/$JOB"
echo "Backup stored under PVC supabase-backups/${TS}/"
