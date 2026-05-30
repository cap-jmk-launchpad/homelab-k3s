#!/usr/bin/env bash
# Enable UFW on anch0r (reverse proxy + k3s worker). Preserves loopback for k3s-agent.
# Run on anch0r as: sudo bash homelab-security-ufw-anch0r.sh
set -euo pipefail

LAN_CIDR="${LAN_CIDR:-192.168.10.0/24}"

if ! command -v ufw >/dev/null 2>&1; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw
fi

# Remove pre-UFW wide HTTP(S) rules if present (keep LAN-scoped rules from this script).
for spec in "80/tcp" "443/tcp"; do
  while sudo ufw status numbered 2>/dev/null | grep -F "${spec}" | grep -q "Anywhere"; do
    num="$(sudo ufw status numbered | grep -F "${spec}" | grep "Anywhere" | head -1 | sed -n 's/^\[\s*\([0-9]*\)\].*/\1/p')"
    [[ -n "${num}" ]] || break
    sudo ufw --force delete "${num}"
  done
done

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow from "${LAN_CIDR}" to any port 80 proto tcp comment 'anch0r http LAN'
sudo ufw allow from "${LAN_CIDR}" to any port 443 proto tcp comment 'anch0r https LAN'
sudo ufw allow from "${LAN_CIDR}" to any port 9100 proto tcp comment 'homelab node-exporter'
sudo ufw allow from "${LAN_CIDR}" to any port 10250 proto tcp comment 'homelab kubelet metrics'
sudo ufw --force enable

# k3s-agent needs loopback before other INPUT rules (kube-router netpol chain)
if ! sudo iptables -C INPUT -i lo -j ACCEPT 2>/dev/null; then
  sudo iptables -I INPUT 1 -i lo -j ACCEPT
fi
# Persist loopback accept for k3s-agent (kube-router chains follow).
if command -v netfilter-persistent >/dev/null 2>&1; then
  sudo netfilter-persistent save || true
fi

echo "OK: anch0r UFW enabled"
sudo ufw status verbose
systemctl is-active k3s-agent
