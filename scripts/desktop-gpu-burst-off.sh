#!/usr/bin/env bash
# Protect desktop GPU for local gaming / daily-driver use (default).
# Run on blackpearl (or any host with kubectl pointing at the homelab cluster).
set -euo pipefail

NODE="${DESKTOP_NODE:-desktop}"
TAINT_KEY="${DESKTOP_GPU_TAINT_KEY:-workload}"
TAINT_VALUE="${DESKTOP_GPU_TAINT_VALUE:-burst}"
TAINT_EFFECT="${DESKTOP_GPU_TAINT_EFFECT:-NoSchedule}"

echo "==> Tainting ${NODE} (${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}) — cluster GPU jobs blocked on desktop"
kubectl taint nodes "$NODE" "${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}" --overwrite

echo "==> Removing burst label from ${NODE}"
kubectl label node "$NODE" burst- --overwrite 2>/dev/null || true

echo "==> Node state"
kubectl get node "$NODE" -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu,WORKLOAD:.metadata.labels.workload,BURST:.metadata.labels.burst,TAINTS:.spec.taints

echo "Desktop GPU is reserved for local use. Run ./scripts/desktop-gpu-burst-on.sh to share it with the cluster."
