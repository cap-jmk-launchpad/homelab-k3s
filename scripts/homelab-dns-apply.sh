#!/usr/bin/env bash
# Apply homelab LAN DNS (CoreDNS on blackpearl :53). Run on blackpearl or via SSH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

kubectl apply -k "$ROOT/k8s/dns/"

echo "Waiting for homelab-lan-coredns..."
kubectl -n homelab-dns rollout status daemonset/homelab-lan-coredns --timeout=120s

if command -v ufw >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  LAN="${HOMELAB_LAN_CIDR:-192.168.10.0/24}"
  sudo ufw allow from "$LAN" to any port 53 proto udp comment homelab-lan-dns || true
  sudo ufw allow from "$LAN" to any port 53 proto tcp comment homelab-lan-dns || true
fi

echo "DNS smoke test (127.0.0.1):"
if command -v nslookup >/dev/null; then
  nslookup grafana.homelab.lan 127.0.0.1 || true
elif command -v dig >/dev/null; then
  dig +short @127.0.0.1 grafana.homelab.lan A || true
fi

echo "Done. Configure Fritz DHCP DNS → 192.168.10.33 — see docs/homelab-lan-dns.md"
