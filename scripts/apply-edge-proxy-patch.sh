#!/usr/bin/env bash
set -euo pipefail
LIC_ROOT="${LIC_ROOT:-${HOME}/staging/lic}"
NET="${LIC_ROOT}/runtime/li_rt_net.c"
sed -i 's/\r$//' "$NET"
python3 - "$NET" <<'PY'
import sys
from pathlib import Path
net = Path(sys.argv[1])
text = net.read_text(encoding="utf-8").replace("\r\n", "\n")
orig = text
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
  /* edge: no cross-pool fallback */"""
if old_fallback in text:
    text = text.replace(old_fallback, new_fallback)
old_lb = """  int32_t peer_port = httpd_route_pool_port_for_request(g_slots[slot].buf, hdr_end, req);
  if (peer_port <= 0) {
    peer_port = httpd_lb_pick_port_for_request(slot, g_slots[slot].buf, hdr_end);
  }"""
new_lb = """  int32_t peer_port = httpd_route_pool_port_for_request(g_slots[slot].buf, hdr_end, req);
  /* edge: vhost routes must not fall back to global LB */"""
if old_lb in text:
    text = text.replace(old_lb, new_lb)
old_acquire_lb = """  int32_t peer_port = httpd_route_pool_port_for_request(g_slots[slot].buf, hdr_end, &req);
  if (peer_port <= 0) {
    peer_port = httpd_lb_pick_port_for_request(slot, g_slots[slot].buf, hdr_end);
  }"""
new_acquire_lb = """  int32_t peer_port = httpd_route_pool_port_for_request(g_slots[slot].buf, hdr_end, &req);
  /* edge: vhost routes must not fall back to global LB */"""
if old_acquire_lb in text:
    text = text.replace(old_acquire_lb, new_acquire_lb)
if text != orig:
    net.write_text(text, encoding="utf-8", newline="\n")
elif "no cross-pool fallback" not in text:
    raise SystemExit("proxy patch: expected blocks not found")
PY
echo "apply-edge-proxy-patch: ok"