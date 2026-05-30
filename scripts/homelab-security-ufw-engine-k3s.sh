#!/usr/bin/env bash
# Engine UFW with k3s/flannel-safe rules (use instead of homelab-security-ufw-engine.sh).
# Run on engine: sudo bash homelab-security-ufw-engine-k3s.sh
set -euo pipefail

LAN_CIDR="${LAN_CIDR:-192.168.10.0/24}"

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default allow routed

sudo ufw allow OpenSSH
sudo ufw allow from "${LAN_CIDR}" to any port 9100 proto tcp comment 'homelab node-exporter'
sudo ufw allow from "${LAN_CIDR}" to any port 10250 proto tcp comment 'homelab kubelet metrics'
sudo ufw allow from "${LAN_CIDR}" to any port 8472 proto udp comment 'flannel vxlan'
sudo ufw allow from "${LAN_CIDR}" to any port 80 proto tcp comment 'engine nginx LAN'

if ! sudo grep -q 'ufw-before-input -i flannel.1' /etc/ufw/before.rules 2>/dev/null; then
  sudo sed -i '/^# don.t delete the .COMMIT. line/i \
# k3s pod networking\
-A ufw-before-input -i flannel.1 -j ACCEPT\
-A ufw-before-output -o flannel.1 -j ACCEPT\
-A ufw-before-forward -i flannel.1 -j ACCEPT\
-A ufw-before-forward -o flannel.1 -j ACCEPT\
-A ufw-before-input -i cni0 -j ACCEPT\
-A ufw-before-forward -i cni0 -j ACCEPT\
-A ufw-before-forward -o cni0 -j ACCEPT\
' /etc/ufw/before.rules
fi

sudo ufw --force enable
sudo ufw reload || true

echo "OK: engine UFW enabled (LAN metrics + flannel)"
sudo ufw status verbose
