#!/usr/bin/env bash
# Install GitLab offsite backup on the engine node (run from laptop with SSH to engine + majico).
#
#   MAJICO_HOST=root@2.31.25.5 MAJICO_SSH_KEY=~/.ssh/majico_vps \
#   ENGINE_HOST=s4il0r@engine ENGINE_SSH_KEY=~/.ssh/homelab \
#     ./scripts/install-engine-gitlab-backup-offsite.sh
#
# Copies age.pub + s3.env from majico (same Hetzner bucket as majico-backup), installs
# rclone/age on engine, systemd timer (daily 05:15 UTC, after full backup + prune).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAJICO_HOST="${MAJICO_HOST:-root@2.31.25.5}"
MAJICO_SSH_KEY="${MAJICO_SSH_KEY:-$HOME/.ssh/majico_vps}"
ENGINE_HOST="${ENGINE_HOST:-s4il0r@engine}"
ENGINE_SSH_KEY="${ENGINE_SSH_KEY:-$HOME/.ssh/homelab}"

ssh_majico=(ssh -o BatchMode=yes -i "$MAJICO_SSH_KEY" "$MAJICO_HOST")
ssh_engine=(ssh -o BatchMode=yes -i "$ENGINE_SSH_KEY" "$ENGINE_HOST")
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ -n "${SSHPASS:-}" ]]; then
  sshpass -e scp -o BatchMode=yes -i "$MAJICO_SSH_KEY" \
    "${MAJICO_HOST}:/etc/majico-backup/s3.env" "${MAJICO_HOST}:/etc/majico-backup/age.pub" "$tmp/"
else
  scp -o BatchMode=yes -i "$MAJICO_SSH_KEY" \
    "${MAJICO_HOST}:/etc/majico-backup/s3.env" "${MAJICO_HOST}:/etc/majico-backup/age.pub" "$tmp/"
fi

"${ssh_engine[@]}" sudo mkdir -p /etc/homelab-backup /usr/local/sbin
"${ssh_engine[@]}" sudo install -m 600 "$tmp/s3.env" /etc/homelab-backup/s3.env
"${ssh_engine[@]}" sudo install -m 644 "$tmp/age.pub" /etc/homelab-backup/age.pub

"${ssh_engine[@]}" 'sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq rclone age'

"${ssh_engine[@]}" sudo install -m 755 "$ROOT/scripts/engine-gitlab-backup-offsite.sh" /usr/local/sbin/engine-gitlab-backup-offsite.sh

"${ssh_engine[@]}" sudo tee /etc/systemd/system/gitlab-backup-offsite.service >/dev/null <<'UNIT'
[Unit]
Description=Homelab GitLab backup to Hetzner Object Storage (encrypted)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
Nice=15
IOSchedulingClass=idle
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/srv/homelab/nvme/gitlab-backups /var/tmp
BindReadOnlyPaths=/etc/homelab-backup
ExecStart=/usr/local/sbin/engine-gitlab-backup-offsite.sh
UNIT

"${ssh_engine[@]}" sudo tee /etc/systemd/system/gitlab-backup-offsite.timer >/dev/null <<'UNIT'
[Unit]
Description=Daily GitLab offsite backup (after in-cluster full + prune)

[Timer]
OnCalendar=*-*-* 05:15:00 UTC
Persistent=true
RandomizedDelaySec=10m

[Install]
WantedBy=timers.target
UNIT

"${ssh_engine[@]}" sudo systemctl daemon-reload
"${ssh_engine[@]}" sudo systemctl enable --now gitlab-backup-offsite.timer
"${ssh_engine[@]}" sudo systemctl list-timers gitlab-backup-offsite.timer --no-pager

echo "Install complete. Test run: ssh $ENGINE_HOST 'sudo /usr/local/sbin/engine-gitlab-backup-offsite.sh'"
