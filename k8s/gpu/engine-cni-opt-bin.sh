#!/bin/bash
# Restore /opt/cni/bin after k3s-agent restart on engine (bridge/tuning plugins).
# Run on engine as root once if GPU/monitoring pods fail with "failed to find plugin".
set -euo pipefail
mkdir -p /opt/cni/bin
for f in /var/lib/rancher/k3s/data/cni/*; do
  ln -sf "$f" "/opt/cni/bin/$(basename "$f")"
done
for f in /usr/lib/cni/*; do
  name=$(basename "$f")
  ln -sf "$f" "/opt/cni/bin/$name"
done
echo "CNI plugins in /opt/cni/bin:"
ls -la /opt/cni/bin
