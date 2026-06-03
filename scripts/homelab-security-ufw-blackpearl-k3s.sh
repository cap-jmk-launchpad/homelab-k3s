#!/usr/bin/env bash
# Blackpearl UFW with k3s/flannel/kube-proxy-safe rules.
# Fixes ClusterIP (10.43.x) "no route to host" when UFW default routed is deny.
#
# Run on blackpearl: sudo bash homelab-security-ufw-blackpearl-k3s.sh
set -euo pipefail

LAN_CIDR="${LAN_CIDR:-192.168.10.0/24}"

delete_rule() {
  local spec="$1"
  while sudo ufw status numbered 2>/dev/null | grep -qF "${spec}"; do
    local num
    num="$(sudo ufw status numbered | grep -F "${spec}" | head -1 | sed -n 's/^\[\s*\([0-9]*\)\].*/\1/p')"
    sudo ufw --force delete "${num}"
  done
}

for port in 6443 30000 30080; do
  delete_rule "${port}/tcp"
  delete_rule "${port}"
done

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default allow routed

sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow from "${LAN_CIDR}" to any port 6443 proto tcp comment 'k3s API LAN'
sudo ufw allow from "${LAN_CIDR}" to any port 30000 proto tcp comment 'staging kong LAN'
sudo ufw allow from "${LAN_CIDR}" to any port 30080 proto tcp comment 'staging app LAN'
sudo ufw allow from "${LAN_CIDR}" to any port 9100 proto tcp comment 'homelab node-exporter'
sudo ufw allow from "${LAN_CIDR}" to any port 10250 proto tcp comment 'homelab kubelet metrics'
sudo ufw allow 8472/udp comment 'flannel vxlan'

if ! sudo ufw status | grep -q '30300/tcp'; then
  sudo ufw allow from "${LAN_CIDR}" to any port 30300 proto tcp comment 'Grafana NodePort LAN'
fi

if ! sudo grep -q 'ufw-before-input -i flannel.1' /etc/ufw/before.rules 2>/dev/null; then
  sudo sed -i '/^# don.t delete the .COMMIT. line/i \
# k3s pod + service networking\
-A ufw-before-input -i lo -j ACCEPT\
-A ufw-before-output -o lo -j ACCEPT\
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

echo "OK: blackpearl UFW (allow routed + flannel/cni0)"
sudo ufw status verbose
