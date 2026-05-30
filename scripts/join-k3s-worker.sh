#!/usr/bin/env bash
# Join this host to blackpearl k3s as an agent (worker).
# Usage (on worker): sudo K3S_URL=https://192.168.10.41:6443 K3S_TOKEN=... ./join-k3s-worker.sh
set -euo pipefail

K3S_URL="${K3S_URL:-https://192.168.10.41:6443}"
K3S_TOKEN="${K3S_TOKEN:?Set K3S_TOKEN from blackpearl: sudo cat /var/lib/rancher/k3s/server/node-token}"
NODE_NAME="${NODE_NAME:-$(hostname -s)}"
NODE_LABELS="${NODE_LABELS:-workload=training,gpu=nvidia,machine=engine}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

export INSTALL_K3S_SKIP_START=false
curl -sfL https://get.k3s.io | K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -s - agent \
  --node-name "$NODE_NAME"

# Labels applied after join from control plane; optional local kubelet config:
echo "Joined as agent. Label from blackpearl:"
echo "  kubectl label node $NODE_NAME ${NODE_LABELS//,/ } --overwrite"
