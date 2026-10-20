#!/usr/bin/env bash
# Upload homelab GitLab NVMe backups to Hetzner Object Storage (age-encrypted).
#
# Expects local artifacts from k8s CronJobs on PVC hostPath:
#   /srv/homelab/nvme/gitlab-backups/{full,hourly,secrets}
#
# Credentials: /etc/homelab-backup/s3.env (RCLONE_CONFIG_HZ_* + S3_BUCKET)
#              /etc/homelab-backup/age.pub
#
# Remote layout: hz:$S3_BUCKET/gitlab/gitlab-YYYYMMDDTHHMM.tar.age
#
# Install: scripts/install-engine-gitlab-backup-offsite.sh (on engine)
set -euo pipefail
umask 077

BACKUP_ROOT="${BACKUP_ROOT:-/srv/homelab/nvme/gitlab-backups}"
CONF_DIR="${CONF_DIR:-/etc/homelab-backup}"

off_fail() {
  logger -t gitlab-backup-offsite -p user.err "FAILED: $*"
  echo "gitlab-backup-offsite FAILED: $*" >&2
  exit 1
}

command -v rclone >/dev/null || off_fail "rclone not installed"
command -v age >/dev/null || off_fail "age not installed"
[[ -r "${CONF_DIR}/s3.env" ]] || off_fail "missing ${CONF_DIR}/s3.env"
[[ -r "${CONF_DIR}/age.pub" ]] || off_fail "missing ${CONF_DIR}/age.pub"

set -a
# shellcheck source=/dev/null
source "${CONF_DIR}/s3.env"
set +a
[[ -n "${S3_BUCKET:-}" ]] || off_fail "S3_BUCKET unset in s3.env"

latest_daily="$(ls -1t "${BACKUP_ROOT}/full/gitlab-full-daily-"*.tar 2>/dev/null | head -1 || true)"
[[ -n "$latest_daily" ]] || off_fail "no gitlab-full-daily-*.tar under ${BACKUP_ROOT}/full"

latest_hourly="$(ls -1t "${BACKUP_ROOT}/hourly/gitlab-db-hourly-"*.sql.gz 2>/dev/null | head -1 || true)"

staged="$(mktemp -d /var/tmp/gitlab-offsite-staging.XXXXXX)"
trap 'rm -rf "$staged"' EXIT
bundle="${staged}/bundle"
mkdir -p "$bundle"

cp -f "$latest_daily" "$bundle/"
if [[ -n "$latest_hourly" ]]; then
  cp -f "$latest_hourly" "$bundle/"
fi
if [[ -d "${BACKUP_ROOT}/secrets" ]]; then
  for f in latest-gitlab-secrets.json latest-gitlab.rb; do
    [[ -f "${BACKUP_ROOT}/secrets/${f}" ]] && cp -f "${BACKUP_ROOT}/secrets/${f}" "$bundle/"
  done
fi

(cd "$bundle" && sha256sum ./* > SHA256SUMS)
(cd "$bundle" && sha256sum -c --quiet SHA256SUMS) || off_fail "staging checksum mismatch"

name="gitlab-$(date -u +%Y%m%dT%H%M)"
enc="$(mktemp "/var/tmp/${name}.XXXXXX.tar.age")"
trap 'rm -rf "$staged" "$enc"' EXIT

tar -C "$staged" -cf - bundle | age -R "${CONF_DIR}/age.pub" -o "$enc" || off_fail "age encrypt"

remote="hz:${S3_BUCKET}/gitlab/${name}.tar.age"
rclone copyto --s3-no-check-bucket "$enc" "$remote" || off_fail "upload ${name}"

lsz="$(stat -c %s "$enc")"
rsz="$(rclone size --json "$remote" | sed -n 's/.*"bytes":\([0-9]*\).*/\1/p')"
[[ "$lsz" = "$rsz" ]] || off_fail "size mismatch local=${lsz} remote=${rsz}"

rclone delete --min-age 30d --include "gitlab-*.tar.age" "hz:${S3_BUCKET}/gitlab/" \
  || logger -t gitlab-backup-offsite -p user.warning "remote retention prune failed"

logger -t gitlab-backup-offsite "OK: ${S3_BUCKET}/gitlab/${name}.tar.age (${rsz} bytes)"
echo "OK: ${remote} (${rsz} bytes)"
