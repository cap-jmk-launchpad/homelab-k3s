#!/usr/bin/env bash
set -euo pipefail
LIC_ROOT="${LIC_ROOT:-${HOME}/staging/lic}"
TLS="${LIC_ROOT}/runtime/li_rt_tls.c"
NET="${LIC_ROOT}/runtime/li_rt_net.c"

python3 - "$TLS" "$NET" <<'PY'
import sys
from pathlib import Path

tls = Path(sys.argv[1]).read_text()
old_tls = """    if (w <= 0) {
      int err = p_SSL_get_error(g_slot_ssl[slot], w);
      if (err == 2 || err == 3 && off == 0) {
        return 0;
      }
      return off > 0 ? (ssize_t)off : -1;
    }"""
new_tls = """    if (w <= 0) {
      int err = p_SSL_get_error(g_slot_ssl[slot], w);
      if (err == 2 || err == 3) {
        return off > 0 ? (ssize_t)off : 0;
      }
      return off > 0 ? (ssize_t)off : -1;
    }"""
if old_tls in tls:
    Path(sys.argv[1]).write_text(tls.replace(old_tls, new_tls, 1))
elif "return off > 0 ? (ssize_t)off : 0;" not in tls:
    raise SystemExit("tls patch: pattern not found")

net = Path(sys.argv[2]).read_text()
old_net = "    if (!g_proxy_snap_recording && !httpd_proxy_relay_pending_client(s) && g_proxy_splice_pipe[0] >= 0) {"
new_net = (
    "    if (!g_proxy_snap_recording && !httpd_proxy_relay_pending_client(s) && g_proxy_splice_pipe[0] >= 0 &&\n"
    "        httpd_tls_slot_proto(slot) != 1) {"
)
if old_net in net and new_net not in net:
    Path(sys.argv[2]).write_text(net.replace(old_net, new_net, 1))
PY

echo "apply-edge-tls-patch: ok"
