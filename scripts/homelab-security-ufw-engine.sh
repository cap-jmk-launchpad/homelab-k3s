#!/usr/bin/env bash
# Enable UFW on engine: SSH + kubelet/node-exporter metrics from LAN only.
# Run on engine as: sudo bash homelab-security-ufw-engine.sh
set -euo pipefail

LAN_CIDR="${LAN_CIDR:-192.168.10.0/24}"

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow from "${LAN_CIDR}" to any port 9100 proto tcp comment 'homelab node-exporter'
sudo ufw allow from "${LAN_CIDR}" to any port 10250 proto tcp comment 'homelab kubelet metrics'
# nginx on :80 (homelab host service)
sudo ufw allow from "${LAN_CIDR}" to any port 80 proto tcp comment 'engine nginx LAN'
sudo ufw --force enable

echo "OK: engine UFW enabled"
sudo ufw status verbose
