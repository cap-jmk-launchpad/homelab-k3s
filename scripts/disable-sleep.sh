#!/usr/bin/env bash
# Always-on staging server — disable sleep, suspend, hibernate.
# Run: sudo bash disable-sleep.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

echo "== mask systemd sleep targets =="
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

echo "== logind: ignore lid/idle sleep =="
install -d -m 755 /etc/systemd/logind.conf.d
cat >/etc/systemd/logind.conf.d/nosleep.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
IdleActionSec=0
EOF

systemctl restart systemd-logind 2>/dev/null || true

echo "== verify =="
systemctl status sleep.target --no-pager || true
echo "---"
cat /etc/systemd/logind.conf.d/nosleep.conf
echo ""
echo "Optional: remove suspend helpers (document only, not auto-removed):"
echo "  apt purge systemd-sleep pm-utils  # only if you know you don't need them"
