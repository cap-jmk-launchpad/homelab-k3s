#!/usr/bin/env bash
# On-demand GitLab backup: Omnibus create + copy to PVC gitlab-backups.
#
# Usage:
#   ./scripts/k8s-gitlab-backup.sh
#   BACKUP_TS=20260101T120000Z ./scripts/k8s-gitlab-restore.sh  # see restore
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NS="${GITLAB_NAMESPACE:-gitlab}"
TS="${BACKUP_TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
JOB="gitlab-backup-manual-${TS}"

kubectl get secret gitlab-secrets -n "$NS" >/dev/null 2>&1 || {
  echo "ERROR: namespace $NS missing gitlab-secrets — run scripts/k8s-gitlab-secret.sh" >&2
  exit 1
}

if kubectl -n "$NS" get cronjob gitlab-backup >/dev/null 2>&1; then
  kubectl -n "$NS" delete job "$JOB" --ignore-not-found
  kubectl -n "$NS" create job "$JOB" --from=cronjob/gitlab-backup
  kubectl -n "$NS" wait --for=condition=complete "job/$JOB" --timeout=3600s
  kubectl -n "$NS" logs "job/$JOB"
  echo "Backup copied to PVC gitlab-backups/ (see job logs for timestamp)."
  exit 0
fi

# Fallback before CronJob is applied: exec directly in Omnibus pod.
POD="$(kubectl get pod -n "$NS" -l app=gitlab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "$POD" ]] || {
  echo "ERROR: no gitlab pod in namespace $NS" >&2
  exit 1
}

SKIP="${GITLAB_BACKUP_SKIP:-registry,artifacts,builds,lfs,packages,terraform_state}"
ART="${TS}_gitlab_backup.tar"
echo "==> gitlab-backup create BACKUP=$TS SKIP=$SKIP (pod $POD)"
kubectl exec -n "$NS" "$POD" -- gitlab-backup create "BACKUP=${TS}" "SKIP=${SKIP}"
kubectl exec -n "$NS" "$POD" -- ls -la "/var/opt/gitlab/backups/${ART}"
echo ""
echo "Tarball on PVC gitlab-data: /var/opt/gitlab/backups/${ART}"
echo "Apply k8s/gitlab backup CronJob for automatic copy to PVC gitlab-backups."
echo "Off-cluster copy:"
echo "  kubectl -n $NS cp $POD:/var/opt/gitlab/backups/${ART} ./${ART}"
