#!/usr/bin/env bash
# Run on each k3s worker (anch0r, deck, desktop) as root if kubectl top / Prometheus
# only see control-plane + engine. Opens LAN scrape paths for node-exporter and kubelet.
set -euo pipefail

LAN_CIDR="${LAN_CIDR:-192.168.10.0/24}"

if command -v ufw >/dev/null 2>&1; then
  ufw allow from "${LAN_CIDR}" to any port 9100 proto tcp comment 'homelab node-exporter'
  ufw allow from "${LAN_CIDR}" to any port 9400 proto tcp comment 'homelab dcgm exporter'
  ufw allow from "${LAN_CIDR}" to any port 10250 proto tcp comment 'homelab kubelet metrics'
  ufw status numbered | grep -E '9100|10250|9400' || true
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${LAN_CIDR} port port=9100 protocol=tcp accept"
  firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${LAN_CIDR} port port=9400 protocol=tcp accept"
  firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=${LAN_CIDR} port port=10250 protocol=tcp accept"
  firewall-cmd --reload
else
  echo "No ufw/firewalld; add iptables rules manually for ${LAN_CIDR} -> 9100, 10250, 9400"
  exit 1
fi

echo "OK: monitoring ports opened for ${LAN_CIDR}"
