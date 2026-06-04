#!/usr/bin/env bash
# List or restore GitLab from a backup tarball on PVC gitlab-backups (or gitlab-data).
#
# Usage:
#   ./scripts/k8s-gitlab-restore.sh
#   BACKUP_TS=20260101T120000Z ./scripts/k8s-gitlab-restore.sh
#
set -euo pipefail

NS="${GITLAB_NAMESPACE:-gitlab}"
BACKUP_TS="${BACKUP_TS:-}"
POD_LS="gitlab-restore-ls-$(date +%s)"

list_backups_pvc() {
  kubectl -n "$NS" run "$POD_LS" --rm -i --restart=Never \
    --image=alpine:3.21 \
    --overrides="$(cat <<EOF
{
  "spec": {
    "nodeSelector": {"kubernetes.io/hostname": "engine"},
    "containers": [{
      "name": "ls",
      "image": "alpine:3.21",
      "command": ["ls", "-1", "/backups"],
      "volumeMounts": [{"name": "b", "mountPath": "/backups"}]
    }],
    "volumes": [{"name": "b", "persistentVolumeClaim": {"claimName": "gitlab-backups"}}]
  }
}
EOF
)" 2>/dev/null || true
}

list_backups_pod() {
  local pod
  pod="$(kubectl get pod -n "$NS" -l app=gitlab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [[ -n "$pod" ]] || return 0
  echo "On gitlab-data (pod $pod):"
  kubectl exec -n "$NS" "$pod" -- ls -1 /var/opt/gitlab/backups/ 2>/dev/null | grep _gitlab_backup.tar || true
}

copy_from_backups_pvc() {
  local art="$1" gl_pod="$2"
  local pod_cp="gitlab-restore-cp-$(date +%s)"
  echo "==> stream ${art} from PVC gitlab-backups into Omnibus pod"
  kubectl -n "$NS" run "$pod_cp" --restart=Never \
    --image=alpine:3.21 \
    --overrides="$(cat <<EOF
{
  "spec": {
    "nodeSelector": {"kubernetes.io/hostname": "engine"},
    "containers": [{
      "name": "cp",
      "image": "alpine:3.21",
      "command": ["cat", "/backups/${art}"],
      "volumeMounts": [{"name": "b", "mountPath": "/backups"}]
    }],
    "volumes": [{"name": "b", "persistentVolumeClaim": {"claimName": "gitlab-backups"}}]
  }
}
EOF
)" >/dev/null
  kubectl -n "$NS" wait --for=condition=Ready "pod/${pod_cp}" --timeout=120s
  kubectl -n "$NS" exec "$pod_cp" -- cat "/backups/${art}" \
    | kubectl exec -i -n "$NS" "$gl_pod" -- sh -c "cat > /var/opt/gitlab/backups/${art}"
  kubectl -n "$NS" delete pod "$pod_cp" --ignore-not-found
}

if [[ -z "$BACKUP_TS" ]]; then
  echo "Available backups on PVC gitlab-backups:"
  list_backups_pvc
  echo ""
  list_backups_pod
  echo ""
  echo "Set BACKUP_TS=<timestamp> (prefix before _gitlab_backup.tar) and re-run." >&2
  exit 1
fi

ART="${BACKUP_TS}_gitlab_backup.tar"
GL_POD="$(kubectl get pod -n "$NS" -l app=gitlab -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$GL_POD" ]] || {
  echo "ERROR: no gitlab pod" >&2
  exit 1
}

echo "==> scale down runner"
kubectl -n "$NS" scale deployment gitlab-runner --replicas=0

if ! kubectl exec -n "$NS" "$GL_POD" -- test -f "/var/opt/gitlab/backups/${ART}" 2>/dev/null; then
  if kubectl get pvc gitlab-backups -n "$NS" >/dev/null 2>&1; then
    copy_from_backups_pvc "$ART" "$GL_POD"
  else
    echo "ERROR: ${ART} not found on gitlab-data; PVC gitlab-backups missing" >&2
    kubectl -n "$NS" scale deployment gitlab-runner --replicas=1
    exit 1
  fi
fi

echo "==> gitlab-backup restore BACKUP=${BACKUP_TS} (stop rails, restore, restart)"
kubectl exec -n "$NS" "$GL_POD" -- gitlab-ctl stop puma sidekiq
kubectl exec -n "$NS" "$GL_POD" -- gitlab-backup restore "BACKUP=${BACKUP_TS}" force=yes
kubectl exec -n "$NS" "$GL_POD" -- gitlab-ctl restart
kubectl exec -n "$NS" "$GL_POD" -- gitlab-rake gitlab:check SANITIZE=true

kubectl -n "$NS" scale deployment gitlab-runner --replicas=1
echo "==> restore complete from ${BACKUP_TS}"
