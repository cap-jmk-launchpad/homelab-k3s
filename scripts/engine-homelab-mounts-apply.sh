#!/usr/bin/env bash
# Apply engine homelab fstab + boot mounts from blackpearl (privileged pod on engine).
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/beelink-cleanup}"
SCRIPT="${REPO_ROOT}/scripts/engine-homelab-fstab-apply.sh"
POD="${REPO_ROOT}/k8s/storage/engine-disk-setup-pod.yaml"

if [[ ! -f "${SCRIPT}" ]]; then
  echo "Missing ${SCRIPT}" >&2
  exit 1
fi

kubectl delete pod engine-disk-setup -n kube-system --ignore-not-found --wait=true 2>/dev/null || true
kubectl apply -f "${POD}"
kubectl wait --for=condition=Ready pod/engine-disk-setup -n kube-system --timeout=180s

python3 -c "
from pathlib import Path
src = Path('${SCRIPT}')
dst = Path('/tmp/engine-homelab-fstab-apply.sh')
dst.write_bytes(src.read_bytes().replace(b'\r\n', b'\n').replace(b'\r', b''))
"

kubectl cp /tmp/engine-homelab-fstab-apply.sh kube-system/engine-disk-setup:setup:/tmp/engine-homelab-fstab-apply.sh -c setup 2>/dev/null || true
cat /tmp/engine-homelab-fstab-apply.sh | kubectl exec -i -n kube-system engine-disk-setup -c setup -- \
  nsenter -t 1 -m -u -i -n -p bash -s

kubectl delete -f "${POD}" --wait=true
echo "Done."
