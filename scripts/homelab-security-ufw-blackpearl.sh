#!/usr/bin/env bash
# Restrict k3s API, staging NodePorts, and Grafana NodePort to LAN on blackpearl.
# Run on blackpearl as: sudo bash homelab-security-ufw-blackpearl.sh
set -euo pipefail

LAN_CIDR="${LAN_CIDR:-192.168.10.0/24}"

delete_rule() {
  local spec="$1"
  while sudo ufw status numbered | grep -qF "${spec}"; do
    local num
    num="$(sudo ufw status numbered | grep -F "${spec}" | head -1 | sed -n 's/^\[\s*\([0-9]*\)\].*/\1/p')"
    sudo ufw --force delete "${num}"
  done
}

for port in 6443 30000 30080; do
  delete_rule "${port}/tcp"
  delete_rule "${port}"
done

sudo ufw allow from "${LAN_CIDR}" to any port 6443 proto tcp comment 'k3s API LAN'
sudo ufw allow from "${LAN_CIDR}" to any port 30000 proto tcp comment 'staging kong LAN'
sudo ufw allow from "${LAN_CIDR}" to any port 30080 proto tcp comment 'staging app LAN'

if ! sudo ufw status | grep -q '30300/tcp'; then
  sudo ufw allow from "${LAN_CIDR}" to any port 30300 proto tcp comment 'Grafana NodePort LAN'
fi

echo "OK: blackpearl UFW LAN restrictions applied"
sudo ufw status numbered | grep -E '6443|30000|30080|30300|OpenSSH' || true
