#!/usr/bin/env bash
# Restore Postgres from a timestamp directory on PVC supabase-backups.
#
# Usage:
#   BACKUP_TS=20260603T030000Z ./scripts/k8s-supabase-restore.sh
#   ./scripts/k8s-supabase-restore.sh   # lists available backups
#
set -euo pipefail

NS="${SUPABASE_NAMESPACE:-supabase}"
BACKUP_TS="${BACKUP_TS:-}"
POD="supabase-restore-$(date +%s)"

if [[ -z "$BACKUP_TS" ]]; then
  echo "Available backups on PVC:"
  kubectl -n "$NS" run "$POD" --rm -i --restart=Never \
    --image=alpine:3.21 \
    --overrides='{"spec":{"nodeSelector":{"kubernetes.io/hostname":"blackpearl"},"containers":[{"name":"ls","image":"alpine:3.21","command":["ls","-1","/backups"],"volumeMounts":[{"name":"b","mountPath":"/backups"}]}],"volumes":[{"name":"b","persistentVolumeClaim":{"claimName":"supabase-backups"}}]}}' \
    2>/dev/null || true
  echo "Set BACKUP_TS=<folder> and re-run." >&2
  exit 1
fi

kubectl get secret supabase-secrets -n "$NS" >/dev/null 2>&1 || {
  echo "ERROR: missing supabase-secrets" >&2
  exit 1
}

echo "==> scale down API workloads"
for dep in kong studio auth rest meta analytics; do
  kubectl -n "$NS" scale deployment "$dep" --replicas=0
done

kubectl -n "$NS" run "$POD" --rm -i --restart=Never \
  --image=postgres:15-alpine \
  --env="PGPASSWORD=$(kubectl get secret supabase-secrets -n "$NS" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)" \
  --overrides="$(cat <<EOF
{
  "spec": {
    "nodeSelector": {"kubernetes.io/hostname": "blackpearl"},
    "containers": [{
      "name": "restore",
      "image": "postgres:15-alpine",
      "stdin": true,
      "tty": true,
      "command": ["sh", "-c", "pg_restore -h db -U postgres -d postgres --clean --if-exists /backups/${BACKUP_TS}/postgres.dump && echo restore_ok"],
      "env": [{"name": "PGPASSWORD", "valueFrom": {"secretKeyRef": {"name": "supabase-secrets", "key": "POSTGRES_PASSWORD"}}}],
      "volumeMounts": [{"name": "b", "mountPath": "/backups"}]
    }],
    "volumes": [{"name": "b", "persistentVolumeClaim": {"claimName": "supabase-backups"}}]
  }
}
EOF
)"

for dep in auth rest meta analytics studio kong; do
  kubectl -n "$NS" scale deployment "$dep" --replicas=1
done

echo "==> restore complete from ${BACKUP_TS}"
