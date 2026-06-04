#!/usr/bin/env bash
# Apply homelab LAN DNS (CoreDNS on blackpearl :53). Run on blackpearl or via SSH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

kubectl apply -k "$ROOT/k8s/dns/"

echo "Waiting for homelab-lan-coredns..."
kubectl -n homelab-dns rollout status daemonset/homelab-lan-coredns --timeout=120s

if command -v ufw >/dev/null 2>&1; then
  LAN="${HOMELAB_LAN_CIDR:-192.168.10.0/24}"
  if sudo ufw allow from "$LAN" to any port 53 proto udp comment homelab-lan-dns && \
     sudo ufw allow from "$LAN" to any port 53 proto tcp comment homelab-lan-dns; then
    echo "UFW: allowed LAN DNS (udp/tcp :53 from ${LAN})"
  else
    echo "WARN: could not add UFW rules for port 53 — run manually:" >&2
    echo "  sudo ufw allow from ${LAN} to any port 53 proto udp comment homelab-lan-dns" >&2
    echo "  sudo ufw allow from ${LAN} to any port 53 proto tcp comment homelab-lan-dns" >&2
  fi
fi

echo "DNS smoke test (127.0.0.1):"
if command -v nslookup >/dev/null; then
  nslookup grafana.homelab.lan 127.0.0.1 || true
elif command -v dig >/dev/null; then
  dig +short @127.0.0.1 grafana.homelab.lan A || true
fi

echo "Done. Configure Fritz DHCP DNS → 192.168.10.33 — see docs/homelab-lan-dns.md"
