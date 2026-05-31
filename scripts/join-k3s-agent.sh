#!/usr/bin/env bash
# Join this host to a k3s cluster as an agent (worker).
# Usage:
#   sudo K3S_URL=https://<control-plane-host>:6443 K3S_TOKEN=... NODE_NAME=<node-name> ./join-k3s-agent.sh
# Optional: NODE_IP=<lan-ip> for --node-ip
set -euo pipefail

K3S_URL="${K3S_URL:?Set K3S_URL e.g. https://<control-plane-host>:6443}"
K3S_TOKEN="${K3S_TOKEN:?Set K3S_TOKEN from control plane: sudo cat /var/lib/rancher/k3s/server/node-token}"
NODE_NAME="${NODE_NAME:-$(hostname -s)}"
NODE_IP="${NODE_IP:-}"
NODE_LABELS="${NODE_LABELS:-}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

AGENT_ARGS=(--node-name "$NODE_NAME")
[[ -n "$NODE_IP" ]] && AGENT_ARGS+=(--node-ip "$NODE_IP")

export INSTALL_K3S_SKIP_START=false
curl -sfL https://get.k3s.io | K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -s - agent "${AGENT_ARGS[@]}"

echo "Joined as agent node: ${NODE_NAME}"
if [[ -n "$NODE_LABELS" ]]; then
  echo "Label from control plane:"
  echo "  kubectl label node ${NODE_NAME} ${NODE_LABELS//,/ } --overwrite"
fi
