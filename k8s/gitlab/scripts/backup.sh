#!/bin/sh
# Runs inside CronJob pod (kubectl + gitlab-backups PVC). Creates Omnibus backup
# in the GitLab pod, then copies the tarball to /backups for off-primary retention.
set -eu

NS="${GITLAB_NAMESPACE:-gitlab}"
TS="${TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
SKIP="${GITLAB_BACKUP_SKIP:-registry,artifacts,builds,lfs,packages,terraform_state}"

POD="$(kubectl get pod -n "$NS" -l app=gitlab -o jsonpath='{.items[0].metadata.name}')"
[ -n "$POD" ] || {
  echo "ERROR: no gitlab pod in namespace $NS" >&2
  exit 1
}

ART="${TS}_gitlab_backup.tar"
echo "==> gitlab-backup create BACKUP=$TS SKIP=$SKIP (pod $POD)"
kubectl exec -n "$NS" "$POD" -- gitlab-backup create "BACKUP=${TS}" "SKIP=${SKIP}"

echo "==> copy to PVC gitlab-backups/$ART"
kubectl cp "${NS}/${POD}:/var/opt/gitlab/backups/${ART}" "/backups/${ART}"

echo "backup_complete ts=${TS} artifact=/backups/${ART}" > "/backups/${TS}.README.txt"
ls -la "/backups/${ART}" "/backups/${TS}.README.txt"
