#!/usr/bin/env bash
# Edge homelab: never proxy to a different upstream pool when the routed peer is down/busy.
set -euo pipefail
LIC_ROOT="${LIC_ROOT:-${HOME}/staging/lic}"
NET="${LIC_ROOT}/runtime/li_rt_net.c"

python3 - "$NET" <<'PY'
import sys
from pathlib import Path

net = Path(sys.argv[1])
text = net.read_text()

text = text.replace("#define HTTPD_MAX_UPSTREAM_PEERS 8", "#define HTTPD_MAX_UPSTREAM_PEERS 32", 1)

old_fallback = """  int up = upstream_pool_acquire(peer_port);
  if (up < 0 && g_up_peer_count > 1) {
    for (int i = 0; i < g_up_peer_count; i++) {
      if (g_up_peers[i].down || g_up_peers[i].port == peer_port) {
        continue;
      }
      peer_port = g_up_peers[i].port;
      up = upstream_pool_acquire(peer_port);
      if (up >= 0) {
        break;
      }
    }
  }"""

new_fallback = """  int up = upstream_pool_acquire(peer_port);
  /* edge: no cross-pool fallback — wrong pool yields 404/400 from alien backends */"""

if old_fallback not in text:
    if "no cross-pool fallback" not in text:
        raise SystemExit("proxy patch: fallback block not found")
else:
    text = text.replace(old_fallback, new_fallback)

old_lb = """  int32_t peer_port = httpd_route_pool_port_for_request(g_slots[slot].buf, hdr_end, req);
  if (peer_port <= 0) {
    peer_port = httpd_lb_pick_port_for_request(slot, g_slots[slot].buf, hdr_end);
  }"""

new_lb = """  int32_t peer_port = httpd_route_pool_port_for_request(g_slots[slot].buf, hdr_end, req);
  /* edge: vhost routes must not fall back to global LB */"""

if old_lb not in text:
    if "must not fall back to global LB" not in text:
        raise SystemExit("proxy patch: lb fallback block not found")
else:
    text = text.replace(old_lb, new_lb)

net.write_text(text)
PY

echo "apply-edge-proxy-patch: ok"
