#!/usr/bin/env bash
# Install gitlab-edge-watchdog systemd timer on blackpearl.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EDGE_DIR="${REPO_ROOT}/k8s/edge"

INSTALL_SYSTEMD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-systemd) INSTALL_SYSTEMD=1; shift ;;
    -h|--help)
      echo "usage: gitlab-edge-watchdog-apply.sh [--install-systemd]"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

install -d /usr/local/bin
install -m 755 "${SCRIPT_DIR}/gitlab-edge-watchdog.sh" /usr/local/bin/gitlab-edge-watchdog.sh

if [[ "$INSTALL_SYSTEMD" -ne 1 ]]; then
  echo "gitlab-edge-watchdog-apply: script installed to /usr/local/bin (pass --install-systemd for timer)"
  exit 0
fi

sed -e "s|/home/s4il0r/staging/homelab-k3s|${REPO_ROOT}|g" \
  "${EDGE_DIR}/gitlab-edge-watchdog.service" >/etc/systemd/system/gitlab-edge-watchdog.service
cp "${EDGE_DIR}/gitlab-edge-watchdog.timer" /etc/systemd/system/gitlab-edge-watchdog.timer
systemctl daemon-reload
systemctl enable --now gitlab-edge-watchdog.timer
systemctl start gitlab-edge-watchdog.service || true
echo "gitlab-edge-watchdog-apply: timer enabled (gitlab-edge-watchdog.timer)"
systemctl list-timers gitlab-edge-watchdog.timer --no-pager || true