#!/usr/bin/env bash
# Ensure blackpearl LAN IP matches k3s node InternalIP (192.168.10.33).
# Without this, kube-proxy DNAT for ClusterIP (10.43.0.1) hits a missing local address.
#
# Run on blackpearl: sudo bash homelab-blackpearl-node-ip-fix.sh
set -euo pipefail

K3S_NODE_IP="${K3S_NODE_IP:-192.168.10.33}"
IFACE="${K3S_NODE_IFACE:-enp1s0}"

if ip -4 addr show dev "$IFACE" | grep -q "${K3S_NODE_IP}/"; then
  echo "OK: ${K3S_NODE_IP} already on ${IFACE}"
  exit 0
fi

ip addr add "${K3S_NODE_IP}/24" dev "$IFACE" 2>/dev/null || true
echo "Added ${K3S_NODE_IP}/24 on ${IFACE}"

DROPIN="/etc/network/interfaces.d/99-k3s-node-ip.cfg"
if [[ ! -f "$DROPIN" ]]; then
  cat >"$DROPIN" <<EOF
# k3s advertises ${K3S_NODE_IP}; keep alias on ${IFACE}
iface ${IFACE} inet static
    address ${K3S_NODE_IP}
    netmask 255.255.255.0
EOF
  echo "Wrote ${DROPIN} (ifupdown will apply on reboot)"
fi

ping -c1 -W1 "${K3S_NODE_IP}" >/dev/null && echo "ping ${K3S_NODE_IP}: OK"
nc -zv -w2 10.43.0.1 443 2>&1 | tail -1 || true
