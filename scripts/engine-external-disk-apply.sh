#!/usr/bin/env bash
# Prepare engine USB disk + apply PV (run on blackpearl).
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/beelink-cleanup}"
NS="${NS:-default}"

echo "==> Preparing engine USB disk (privileged setup pod on engine)"
kubectl apply -f "${REPO_ROOT}/k8s/storage/engine-disk-setup-pod.yaml"
kubectl wait --for=condition=Ready pod/engine-disk-setup -n kube-system --timeout=120s
python3 <<'PY'
from pathlib import Path
import os
src = Path(os.environ["REPO_ROOT"]) / "scripts/engine-external-disk-setup.sh"
dst = Path("/tmp/engine-external-disk-setup.sh")
dst.write_bytes(src.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b""))
PY
sed 's/\r$//' /tmp/engine-external-disk-setup.sh | kubectl exec -i -n kube-system engine-disk-setup -c setup -- \
  nsenter -t 1 -m -u -i -n -p bash -s
kubectl delete -f "${REPO_ROOT}/k8s/storage/engine-disk-setup-pod.yaml" --wait=true

echo "==> Applying PV / StorageClass"
kubectl apply -f "${REPO_ROOT}/k8s/storage/engine-external-pv.yaml"

echo "==> Verify"
kubectl get pv engine-external-data
kubectl debug node/engine --image=busybox:1.36 --profile=general \
  -- chroot /host df -hT /srv/homelab/external 2>&1 | tail -5

echo "Done. Create PVCs with storageClassName: engine-external (pods on engine)."
