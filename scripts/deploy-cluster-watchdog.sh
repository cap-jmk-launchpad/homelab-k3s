#!/usr/bin/env bash
# Deploy the unified cluster-watchdog to blackpearl (run as root on blackpearl).
# Installs: /usr/local/bin/cluster-watchdog.sh + services.conf,
#           systemd unit + timer (every 5 min), arms the timer.
# Retires the now-duplicate watchdogs that this single service replaces:
#   - li-httpd-edge-watchdog.timer  (was edge-watchdog.sh)
#   - gitlab-edge-watchdog.timer    (was gitlab-edge-watchdog.sh)
# Usage: sudo bash scripts/deploy-cluster-watchdog.sh [--retire-redundant-cronjobs]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WD_DIR="${REPO_ROOT}/k8s/monitoring/cluster-watchdog"

# blackpearl runs kubectl as root; point at the s4il0r kubeconfig the control plane uses.
export KUBECONFIG="${KUBECONFIG:-/home/s4il0r/.kube/config}"

[[ "$(id -u)" -eq 0 ]] || { echo "run as root on blackpearl" >&2; exit 1; }

RETIRE_CRONJOBS=0
for arg in "$@"; do
  case "$arg" in
    --retire-redundant-cronjobs) RETIRE_CRONJOBS=1 ;;
    -h|--help) echo "usage: sudo bash scripts/deploy-cluster-watchdog.sh [--retire-redundant-cronjobs]"; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

install -m 755 "${SCRIPT_DIR}/cluster-watchdog.sh" /usr/local/bin/cluster-watchdog.sh
install -d /etc/cluster-watchdog
install -m 644 "${WD_DIR}/services.conf" /etc/cluster-watchdog/services.conf

# systemd unit + timer (rewrite REPO_ROOT path to match this checkout)
sed "s|/home/s4il0r/staging/homelab-k3s|${REPO_ROOT}|g" \
  "${WD_DIR}/cluster-watchdog.service" > /etc/systemd/system/cluster-watchdog.service
install -m 644 "${WD_DIR}/cluster-watchdog.timer" /etc/systemd/system/cluster-watchdog.timer

systemctl daemon-reload
systemctl enable --now cluster-watchdog.timer
systemctl start cluster-watchdog.service || true   # one immediate run

echo "cluster-watchdog: timer installed and enabled (every 5 min)"
systemctl list-timers cluster-watchdog.timer --no-pager || true

# --- retire the duplicate watchdog timers this service replaces ---
# NOTE: `systemctl mask` refuses to overwrite a pre-existing regular unit file
# ("Failed to mask unit: File already exists"). The legacy timers here were
# installed that way, so we drop the stale file first, then mask (-> symlink to
# /dev/null). We verify the masked state and FAIL LOUD if it didn't take, so a
# retirement that silently leaves the timer armable can never be misreported.
for unit in li-httpd-edge-watchdog.timer gitlab-edge-watchdog.timer; do
  if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
    systemctl stop "${unit%.timer}.service" 2>/dev/null || true
    systemctl disable "$unit" 2>/dev/null || true
    stale="/etc/systemd/system/$unit"
    if [[ -e "$stale" && ! -L "$stale" ]]; then rm -f "$stale"; fi
    if systemctl mask "$unit" 2>/dev/null; then :; else
      echo "cluster-watchdog: WARN initial mask of $unit failed; retrying via symlink" >&2
      ln -sf /dev/null "$stale"
    fi
    if [[ "$(systemctl is-enabled "$unit" 2>/dev/null)" == "masked" ]]; then
      echo "cluster-watchdog: retired $unit (masked)"
    else
      echo "cluster-watchdog: ERROR failed to mask $unit — still armable" >&2
      exit 1
    fi
  else
    echo "cluster-watchdog: $unit not installed (nothing to retire)"
  fi
done
systemctl daemon-reload

if [[ "$RETIRE_CRONJOBS" -eq 1 ]]; then
  # The unified watchdog rotates backups itself; the per-stack prune CronJobs are now redundant.
  for cj in supabase/supabase-backup-prune librebase-supabase/librebase-supabase-backup-prune agentic-book-supabase/agentic-book-supabase-backup-prune; do
    ns="${cj%/*}"; name="${cj#*/}"
    if kubectl get cronjob -n "$ns" "$name" >/dev/null 2>&1; then
      kubectl patch cronjob -n "$ns" "$name" -p='{"spec":{"suspend":true}}' --type=merge 2>/dev/null || true
      echo "cluster-watchdog: suspended $ns/$name (rotation now owned by watchdog)"
    fi
  done
fi

echo "cluster-watchdog: deploy complete"
