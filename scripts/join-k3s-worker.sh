#!/usr/bin/env bash
# Join this host to blackpearl k3s as an agent (worker).
# Usage (on worker): sudo K3S_URL=https://192.168.10.41:6443 K3S_TOKEN=... ./join-k3s-worker.sh
# Optional: MAX_PODS=250 for dense workers (PodCIDR /24 allows up to ~254)
set -euo pipefail

K3S_URL="${K3S_URL:-https://192.168.10.41:6443}"
K3S_TOKEN="${K3S_TOKEN:?Set K3S_TOKEN from blackpearl: sudo cat /var/lib/rancher/k3s/server/node-token}"
NODE_NAME="${NODE_NAME:-$(hostname -s)}"
NODE_LABELS="${NODE_LABELS:-workload=training,gpu=nvidia,machine=engine}"
MAX_PODS="${MAX_PODS:-250}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if [[ -n "$MAX_PODS" ]]; then
  MAX_PODS="$MAX_PODS" bash "$SCRIPT_DIR/k3s-write-kubelet-max-pods.sh"
fi

export INSTALL_K3S_SKIP_START=false
curl -sfL https://get.k3s.io | K3S_URL="$K3S_URL" K3S_TOKEN="$K3S_TOKEN" sh -s - agent \
  --node-name "$NODE_NAME"

echo "Joined as agent. Label from blackpearl:"
echo "  kubectl label node $NODE_NAME ${NODE_LABELS//,/ } --overwrite"
if [[ -n "$MAX_PODS" ]]; then
  echo "Kubelet max-pods=${MAX_PODS}"
fi