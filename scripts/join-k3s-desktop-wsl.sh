#!/usr/bin/env bash
# Join desktop Ubuntu WSL to blackpearl k3s. Run inside WSL as root:
#   sudo bash join-k3s-desktop-wsl.sh
# Or from PowerShell:
#   wsl -d Ubuntu-24.04 -u root -- bash /mnt/c/.../join-k3s-desktop-wsl.sh
set -euo pipefail

K3S_URL="${K3S_URL:-https://192.168.10.41:6443}"
K3S_TOKEN="${K3S_TOKEN:?Set K3S_TOKEN from blackpearl: sudo cat /var/lib/rancher/k3s/server/node-token}"
NODE_NAME="${NODE_NAME:-desktop}"
NODE_IP="${NODE_IP:-192.168.10.31}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if systemctl is-active --quiet k3s-agent 2>/dev/null; then
  echo "k3s-agent already running"
  exit 0
fi

curl -sfL https://get.k3s.io | K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -s - agent \
  --node-name "$NODE_NAME" \
  --node-ip "$NODE_IP" \
  --flannel-iface eth0

systemctl enable --now k3s-agent
echo "Joined as $NODE_NAME ($NODE_IP)"
