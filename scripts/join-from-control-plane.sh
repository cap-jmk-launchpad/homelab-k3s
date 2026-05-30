#!/usr/bin/env bash
# Join a worker using homelab SSH key (run on control plane).
# Usage:
#   WORKER_HOST=<admin-user>@<lan-ip> NODE_NAME=<node-name> bash join-from-control-plane.sh
# WSL / custom SSH port:
#   SSH_PORT=2222 WORKER_HOST=<admin-user>@<lan-ip> NODE_NAME=<node-name> bash join-from-control-plane.sh
set -euo pipefail

WORKER_HOST="${WORKER_HOST:?Set WORKER_HOST e.g. <admin-user>@<lan-ip>}"
NODE_NAME="${NODE_NAME:-$(echo "$WORKER_HOST" | cut -d@ -f1)}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/homelab}"
K3S_URL="${K3S_URL:-https://<control-plane-host>:6443}"
SSH_PORT="${SSH_PORT:-22}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -f /var/lib/rancher/k3s/server/node-token ]]; then
  echo "node-token not found. Run this script on the k3s control plane." >&2
  exit 1
fi

TOKEN="$(sudo cat /var/lib/rancher/k3s/server/node-token)"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -p "$SSH_PORT")
[[ -f "$SSH_KEY" ]] && SSH_OPTS+=(-i "$SSH_KEY")

scp "${SSH_OPTS[@]}" "$SCRIPT_DIR/join-k3s-agent.sh" "$WORKER_HOST:~/join-k3s-agent.sh"
ssh -t "${SSH_OPTS[@]}" "$WORKER_HOST" \
  "chmod +x ~/join-k3s-agent.sh && sudo K3S_URL=${K3S_URL} K3S_TOKEN='${TOKEN}' NODE_NAME=${NODE_NAME} ~/join-k3s-agent.sh"

sleep 10
if command -v kubectl &>/dev/null; then
  kubectl get node "$NODE_NAME" -o wide 2>/dev/null || kubectl get nodes
else
  echo "kubectl not in PATH; verify node ${NODE_NAME} from control plane."
fi
