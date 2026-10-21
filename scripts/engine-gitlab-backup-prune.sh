#!/usr/bin/env bash
# GitLab backup retention on engine — prune PVC gitlab-backup-storage + Omnibus tars in gitlab-data.
# KEEP_HOURLY=24, KEEP_FULL_DAILY=7 (mirrors manual 2026-07-15 rotation).
#
# Run from workstation with kubectl:
#   bash homelab-k3s/scripts/engine-gitlab-backup-prune.sh
# Or on engine (host paths):
#   KEEP_HOURLY=24 KEEP_FULL_DAILY=7 bash engine-gitlab-backup-prune.sh --host
set -euo pipefail

KEEP_HOURLY="${KEEP_HOURLY:-24}"
KEEP_FULL_DAILY="${KEEP_FULL_DAILY:-7}"
NS="${GITLAB_NS:-gitlab}"
DRY_RUN="${DRY_RUN:-0}"

prune_dir() {
  local dir="$1" pattern="$2" keep="$3" label="$4"
  [[ -d "$dir" ]] || { echo "skip ${label}: ${dir} missing"; return 0; }
  mapfile -t files < <(find "$dir" -maxdepth 1 -type f -name "$pattern" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
  local n=${#files[@]}
  echo "${label}: ${n} files in ${dir} (keep ${keep})"
  local i=0
  for f in "${files[@]}"; do
    i=$((i + 1))
    if [[ "$i" -le "$keep" ]]; then
      continue
    fi
    echo "  delete ${f}"
    if [[ "${DRY_RUN}" != "1" ]]; then
      rm -f "$f"
    fi
  done
}

host_paths() {
  local backup_pv data_pv
  backup_pv=$(kubectl get pvc gitlab-backup-storage -n "$NS" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
  data_pv=$(kubectl get pvc gitlab-data -n "$NS" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
  BACKUP_ROOT=""
  DATA_BACKUP_ROOT=""
  if [[ -n "$backup_pv" ]]; then
    BACKUP_ROOT=$(kubectl get pv "$backup_pv" -o jsonpath='{.spec.local.path}{.spec.hostPath.path}' 2>/dev/null || true)
  fi
  if [[ -n "$data_pv" ]]; then
    local data_root
    data_root=$(kubectl get pv "$data_pv" -o jsonpath='{.spec.local.path}{.spec.hostPath.path}' 2>/dev/null || true)
    DATA_BACKUP_ROOT="${data_root}/backups"
  fi
}

if [[ "${1:-}" == "--host" ]]; then
  if [[ "$(id -u)" -ne 0 ]]; then
    exec sudo env KEEP_HOURLY="${KEEP_HOURLY}" KEEP_FULL_DAILY="${KEEP_FULL_DAILY}" DRY_RUN="${DRY_RUN}" bash "$0" --host
  fi
  host_paths
  echo "=== gitlab-backup-prune (host) KEEP_HOURLY=${KEEP_HOURLY} KEEP_FULL_DAILY=${KEEP_FULL_DAILY} ==="
  [[ -n "${BACKUP_ROOT:-}" ]] && prune_dir "${BACKUP_ROOT}" 'gitlab-db-*.dump' "${KEEP_HOURLY}" 'hourly-db'
  [[ -n "${BACKUP_ROOT:-}" ]] && prune_dir "${BACKUP_ROOT}" 'gitlab-full-*.tar' "${KEEP_FULL_DAILY}" 'full-daily'
  [[ -n "${DATA_BACKUP_ROOT:-}" ]] && prune_dir "${DATA_BACKUP_ROOT}" '*_gitlab_backup.tar' "${KEEP_FULL_DAILY}" 'omnibus-data'
  exit 0
fi

echo "=== gitlab-backup-prune via kubectl exec ==="
POD=$(kubectl get pod -n "$NS" -l app=gitlab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
  echo "gitlab pod not found — falling back to --host on engine"
  exec bash "$0" --host
fi

kubectl exec -n "$NS" "$POD" -- sh -c "
  set -eu
  KEEP_HOURLY=${KEEP_HOURLY}
  KEEP_FULL_DAILY=${KEEP_FULL_DAILY}
  DRY=${DRY_RUN}
  prune() {
    dir=\$1; pat=\$2; keep=\$3; label=\$4
    [ -d \"\$dir\" ] || return 0
    ls -1t \"\$dir\"/\$pat 2>/dev/null | awk -v k=\$keep 'NR>k {print}' | while read -r f; do
      echo \"  delete \$f\"
      [ \"\$DRY\" = \"1\" ] || rm -f \"\$f\"
    done
  }
  echo 'omnibus backups in /var/opt/gitlab/backups'
  prune /var/opt/gitlab/backups '*_gitlab_backup.tar' \"\$KEEP_FULL_DAILY\" omnibus
"

host_paths
if [[ -n "${BACKUP_ROOT:-}" ]]; then
  echo "=== gitlab-backup-storage PVC at ${BACKUP_ROOT} ==="
  ssh -o BatchMode=yes -o ConnectTimeout=5 "${ENGINE_SSH:-s4il0r@192.168.10.40}" \
    "sudo env KEEP_HOURLY=${KEEP_HOURLY} KEEP_FULL_DAILY=${KEEP_FULL_DAILY} DRY_RUN=${DRY_RUN} BACKUP_ROOT='${BACKUP_ROOT}' bash -s" <<'HOST'
set -eu
prune_dir() {
  dir="$1"; pattern="$2"; keep="$3"; label="$4"
  [ -d "$dir" ] || return 0
  ls -1t "$dir"/$pattern 2>/dev/null | awk -v k="$keep" 'NR>k {print}' | while read -r f; do
    echo "  delete $f"
    [ "${DRY_RUN:-0}" = "1" ] || rm -f "$f"
  done
}
prune_dir "${BACKUP_ROOT}" 'gitlab-db-*.dump' "${KEEP_HOURLY}" hourly-db
prune_dir "${BACKUP_ROOT}" 'gitlab-full-*.tar' "${KEEP_FULL_DAILY}" full-daily
HOST
fi

echo "=== done ==="
