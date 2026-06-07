#!/usr/bin/env bash
# Wipe engine NVMe LUKS, format ext4, mount /srv/homelab/nvme + apply PV (run on blackpearl).
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/beelink-cleanup}"
SCRIPT="${REPO_ROOT}/scripts/engine-nvme-disk-setup.sh"
POD="${REPO_ROOT}/k8s/storage/engine-disk-setup-pod.yaml"

if [[ ! -f "${SCRIPT}" ]]; then
  echo "Missing ${SCRIPT}" >&2
  exit 1
fi

echo "==> Preparing engine NVMe (LUKS wipe + ext4 @ /srv/homelab/nvme)"
kubectl apply -f "${POD}"
kubectl wait --for=condition=Ready pod/engine-disk-setup -n kube-system --timeout=120s

TMP="/tmp/engine-nvme-disk-setup.sh"
python3 -c "from pathlib import Path; p=Path('${SCRIPT}'); Path('${TMP}').write_bytes(p.read_bytes().replace(b'\\r\\n',b'\\n').replace(b'\\r',b''))"
sed 's/\r$//' "${TMP}" | kubectl exec -i -n kube-system engine-disk-setup -c setup -- \
  nsenter -t 1 -m -u -i -n -p bash -s

kubectl delete -f "${POD}" --wait=true

echo "==> Applying PV / StorageClass"
kubectl apply -f "${REPO_ROOT}/k8s/storage/engine-nvme-pv.yaml"

echo "==> Verify"
kubectl get pv engine-nvme-data
kubectl debug node/engine --image=busybox:1.36 --profile=general --quiet -- \
  chroot /host df -hT /srv/homelab/nvme 2>&1 | tail -3

echo "Done. PVCs: storageClassName: engine-nvme (pods on engine)."
