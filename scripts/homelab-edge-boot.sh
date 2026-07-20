#!/usr/bin/env bash
# blackpearl boot recovery — k3s node IP alias, edge configs, GitLab upstream heal.
# Installed as homelab-edge-boot.service (oneshot, RemainAfterExit=yes).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_TAG="homelab-edge-boot"

log() { echo "${LOG_TAG}: $*"; }

wait_k3s() {
  local i max="${EDGE_BOOT_K3S_WAIT_SEC:-180}"
  for ((i = 1; i <= max; i++)); do
    if kubectl cluster-info >/dev/null 2>&1; then
      log "kubectl ready (${i}s)"
      return 0
    fi
    sleep 1
  done
  log "kubectl not ready after ${max}s (continuing edge-only heal)"
  return 1
}

run_if() {
  local path="$1"
  shift
  if [[ -x "$path" || -f "$path" ]]; then
    bash "$path" "$@" || log "WARN: $path exited non-zero"
  else
    log "skip missing: $path"
  fi
}

log "starting boot recovery (repo=${REPO_ROOT})"

# k3s advertises 192.168.10.33; restore alias when DHCP moved admin IP (e.g. .41).
run_if "${SCRIPT_DIR}/homelab-blackpearl-node-ip-fix.sh"

wait_k3s || true

LIS_APPLY="${SCRIPT_DIR}/edge-lis-apply.sh"
NGINX_APPLY="${SCRIPT_DIR}/edge-nginx-apply.sh"
if [[ ! -f "$LIS_APPLY" ]]; then
  LIS_APPLY="/home/s4il0r/staging/homelab-k3s/scripts/edge-lis-apply.sh"
fi
if [[ ! -f "$NGINX_APPLY" ]]; then
  NGINX_APPLY="/home/s4il0r/staging/homelab-k3s/scripts/edge-nginx-apply.sh"
fi

run_if "$LIS_APPLY" --no-reload
run_if "$NGINX_APPLY" --no-reload

# Multi-tenant WAN MX (:25 domain → NodePorts) + submission/IMAP REDIRECTs.
MX_APPLY="${SCRIPT_DIR}/edge-mail-mx-router-apply.sh"
if [[ ! -f "$MX_APPLY" ]]; then
  MX_APPLY="/home/s4il0r/staging/homelab-k3s/scripts/edge-mail-mx-router-apply.sh"
fi
run_if "$MX_APPLY"

for unit in li-httpd-homelab.service nginx-gitlab-edge.service postfix-mx-router.service; do
  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    systemctl restart "$unit" 2>/dev/null || systemctl start "$unit" 2>/dev/null || \
      log "WARN: could not start ${unit}"
  fi
done

# Full GitLab upstream / NodePort / pod heal (same as timer oneshot).
if [[ -x /usr/local/bin/gitlab-edge-watchdog.sh ]]; then
  /usr/local/bin/gitlab-edge-watchdog.sh || log "WARN: gitlab-edge-watchdog non-zero"
elif [[ -f "${SCRIPT_DIR}/gitlab-edge-watchdog.sh" ]]; then
  bash "${SCRIPT_DIR}/gitlab-edge-watchdog.sh" || log "WARN: gitlab-edge-watchdog non-zero"
fi

# Ensure periodic heal timers are armed after reboot.
for timer in gitlab-edge-watchdog.timer li-httpd-edge-watchdog.timer cluster-health-watchdog.timer; do
  if systemctl list-unit-files "$timer" >/dev/null 2>&1; then
    systemctl enable "$timer" 2>/dev/null || true
    systemctl start "$timer" 2>/dev/null || true
  fi
done

log "boot recovery complete"
