#!/usr/bin/env bash
# Deploy homelab edge scripts + systemd units on blackpearl (run from repo root).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDGE="${REPO_ROOT}/k8s/edge"

[[ "$(id -u)" -eq 0 ]] || { echo "run as root on blackpearl" >&2; exit 1; }

git -C "${REPO_ROOT}" checkout -- scripts/reorder-edge-upstream-peers.py scripts/edge-health-probe.sh scripts/edge-watchdog.sh scripts/edge-lis-apply.sh scripts/deploy-edge-blackpearl.sh 2>/dev/null || true
sed -i 's/\r$//' "${REPO_ROOT}"/scripts/*.sh 2>/dev/null || true

install -m 755 "${REPO_ROOT}/scripts/edge-lis-apply.sh" "${REPO_ROOT}/scripts/edge-health-probe.sh"
install -m 755 "${REPO_ROOT}/scripts/edge-watchdog.sh" "${REPO_ROOT}/scripts/reorder-edge-upstream-peers.py"
install -m 755 "${REPO_ROOT}/scripts/edge-health-probe.sh" /usr/local/bin/edge-health-probe.sh

HOME=/home/s4il0r LIC_ROOT=/home/s4il0r/staging/lic LI_HTTPD_ROOT=/home/s4il0r/staging/li-httpd \
  bash "${REPO_ROOT}/scripts/edge-lis-apply.sh" --install-systemd

systemctl restart li-httpd-homelab.service
sleep 2
systemctl restart li-httpd-homelab-tls.service
systemctl enable --now li-httpd-edge-watchdog.timer

systemctl is-active li-httpd-homelab.service li-httpd-homelab-tls.service li-httpd-edge-watchdog.timer
echo "deploy-edge-blackpearl: done"
