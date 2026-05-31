#!/usr/bin/env bash
# Opt in to sharing the desktop GPU with cluster burst / multi-GPU jobs.
# Run on blackpearl only when you are NOT gaming on the desktop.
set -euo pipefail

NODE="${DESKTOP_NODE:-desktop}"
TAINT_KEY="${DESKTOP_GPU_TAINT_KEY:-workload}"
TAINT_VALUE="${DESKTOP_GPU_TAINT_VALUE:-burst}"
TAINT_EFFECT="${DESKTOP_GPU_TAINT_EFFECT:-NoSchedule}"

echo "==> Removing ${NODE} taint ${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}"
kubectl taint nodes "$NODE" "${TAINT_KEY}=${TAINT_VALUE}:${TAINT_EFFECT}-" 2>/dev/null || true

echo "==> Labeling ${NODE} burst=enabled (required by burst job nodeAffinity)"
kubectl label node "$NODE" burst=enabled --overwrite

echo "==> Node state"
kubectl get nodes engine "$NODE" -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu,WORKLOAD:.metadata.labels.workload,BURST:.metadata.labels.burst,TAINTS:.spec.taints

echo "Desktop GPU is shared with the cluster. Run ./scripts/desktop-gpu-burst-off.sh when you start gaming."
