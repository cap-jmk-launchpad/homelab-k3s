#!/usr/bin/env bash
# On-demand GitLab Omnibus backup (stored in pod PVC under /var/opt/gitlab/backups).
#
# Usage:
#   ./scripts/k8s-gitlab-backup.sh
#   BACKUP_TS=20260101T120000Z ./scripts/k8s-gitlab-backup.sh
#
set -euo pipefail

NS="${GITLAB_NAMESPACE:-gitlab}"
TS="${BACKUP_TS:-$(date -u +%Y%m%dT%H%M%SZ)}"

POD="$(kubectl get pod -n "$NS" -l app=gitlab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "$POD" ]] || {
  echo "ERROR: no gitlab pod in namespace $NS" >&2
  exit 1
}

echo "==> gitlab-backup create BACKUP=$TS (pod $POD)"
kubectl exec -n "$NS" "$POD" -- gitlab-backup create BACKUP="$TS"
kubectl exec -n "$NS" "$POD" -- ls -la "/var/opt/gitlab/backups/" | tail -5
echo "Backup artifact on PVC gitlab-data (path above). Copy off-cluster for DR:"
echo "  kubectl -n $NS exec $POD -- tar czf - /var/opt/gitlab/backups/${TS}_gitlab_backup.tar"
