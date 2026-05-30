#!/usr/bin/env bash
# Fix engine k3s CNI: pods must use flannel (10.42.x), not podman bridge (10.88.x).
# Run on engine as root after podman package installs /etc/cni/net.d/87-podman-bridge.conflist.
set -euo pipefail

PODMAN_CNI="/etc/cni/net.d/87-podman-bridge.conflist"
FLANNEL_CNI="/var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist"

if [[ -f "$PODMAN_CNI" ]]; then
  mv "$PODMAN_CNI" "${PODMAN_CNI}.disabled"
  echo "Disabled podman CNI: ${PODMAN_CNI}.disabled"
fi

mkdir -p /etc/cni/net.d
if [[ -f "$FLANNEL_CNI" ]]; then
  cp -f "$FLANNEL_CNI" /etc/cni/net.d/10-flannel.conflist
  echo "Installed k3s flannel into /etc/cni/net.d/"
fi

# CNI plugin symlinks (GPU/monitoring pods)
if [[ -x /var/lib/rancher/k3s/data/cni/bridge ]]; then
  mkdir -p /opt/cni/bin
  for f in /var/lib/rancher/k3s/data/cni/*; do
    ln -sf "$f" "/opt/cni/bin/$(basename "$f")"
  done
  for f in /usr/lib/cni/*; do
    ln -sf "$f" "/opt/cni/bin/$(basename "$f")"
  done
fi

systemctl restart k3s-agent
echo "Restarted k3s-agent; wait for Ready, then recycle engine monitoring pods if still on 10.88.x:"
echo "  kubectl delete pod -n monitoring -l app.kubernetes.io/name=prometheus --field-selector spec.nodeName=engine"
echo "  kubectl delete pod -n monitoring -l app=dcgm-exporter --field-selector spec.nodeName=engine"
