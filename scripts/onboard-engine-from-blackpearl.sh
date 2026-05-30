#!/usr/bin/env bash
# Run on blackpearl after SSH to engine works (s4il0r@192.168.10.32).
set -euo pipefail
ENGINE_HOST="${ENGINE_HOST:-s4il0r@192.168.10.32}"
K3S_URL="${K3S_URL:-https://192.168.10.41:6443}"
TOKEN="$(sudo cat /var/lib/rancher/k3s/server/node-token)"
REPO="${REPO:-$HOME/staging/beelink-cleanup}"

echo "==> copy join scripts to engine"
ssh -o StrictHostKeyChecking=accept-new "$ENGINE_HOST" "mkdir -p ~/k3s-join"
scp -o StrictHostKeyChecking=accept-new "$REPO/scripts/join-k3s-worker.sh" "$REPO/scripts/setup-engine-access.sh" "$ENGINE_HOST:~/k3s-join/"

echo "==> join k3s agent on engine (needs sudo on engine)"
ssh -t "$ENGINE_HOST" "chmod +x ~/k3s-join/join-k3s-worker.sh && sudo K3S_URL=$K3S_URL K3S_TOKEN='$TOKEN' NODE_NAME=engine ~/k3s-join/join-k3s-worker.sh"

echo "==> label node"
sleep 5
kubectl label node engine workload=training gpu=nvidia machine=engine --overwrite
kubectl get nodes -o wide

echo "==> install NVIDIA device plugin (if nvidia-smi works on engine)"
if ssh "$ENGINE_HOST" "command -v nvidia-smi && nvidia-smi -L" 2>/dev/null; then
  kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.0/deployments/static/nvidia-device-plugin.yml
  echo "Device plugin applied. Verify: kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds"
else
  echo "Skip GPU plugin — nvidia-smi not found on engine"
fi
