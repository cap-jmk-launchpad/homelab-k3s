#!/usr/bin/env bash
# Join a worker using homelab SSH key (run on blackpearl).
# Usage: WORKER_HOST=s4il0r@192.168.10.31 NODE_NAME=desktop bash join-worker-from-blackpearl.sh
# Desktop WSL uses SSH port 2222: SSH_PORT=2222 WORKER_HOST=s4il0r@192.168.10.31 ...
set -euo pipefail
WORKER_HOST="${WORKER_HOST:?Set WORKER_HOST e.g. s4il0r@192.168.10.31}"
NODE_NAME="${NODE_NAME:-$(echo "$WORKER_HOST" | cut -d@ -f1)}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/homelab}"
K3S_URL="${K3S_URL:-https://192.168.10.41:6443}"
TOKEN="$(sudo cat /var/lib/rancher/k3s/server/node-token)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SSH_PORT="${SSH_PORT:-22}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -p "$SSH_PORT")
[[ -f "$SSH_KEY" ]] && SSH_OPTS+=(-i "$SSH_KEY")

scp "${SSH_OPTS[@]}" "$SCRIPT_DIR/join-k3s-worker.sh" "$WORKER_HOST:~/join-k3s-worker.sh"
ssh -t "${SSH_OPTS[@]}" "$WORKER_HOST" "chmod +x ~/join-k3s-worker.sh && sudo K3S_URL=$K3S_URL K3S_TOKEN='$TOKEN' NODE_NAME=$NODE_NAME ~/join-k3s-worker.sh"

sleep 10
kubectl label node "$NODE_NAME" workload=burst machine=daily-driver --overwrite 2>/dev/null || kubectl get nodes
