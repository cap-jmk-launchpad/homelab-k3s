#!/usr/bin/env bash
# Rebuild /usr/local/bin/li-httpd on blackpearl for multi-site vhost edge routing.
set -euo pipefail

LIC_ROOT="${LIC_ROOT:-${HOME}/staging/lic}"
LI_HTTPD_ROOT="${LI_HTTPD_ROOT:-${HOME}/staging/li-httpd}"
NET_C="${LIC_ROOT}/runtime/li_rt_net.c"
BUILD_LI="${LIC_ROOT}/scripts/build-li-httpd.sh"

[[ -f "$NET_C" ]] || { echo "missing $NET_C" >&2; exit 1; }
[[ -f "$BUILD_LI" ]] || { echo "missing $BUILD_LI" >&2; exit 1; }

if [[ -f "${LI_HTTPD_ROOT}/scripts/patch-vhost-runtime.py" ]] \
  && [[ -d "${LIC_ROOT}/.git" ]]; then
  python3 "${LI_HTTPD_ROOT}/scripts/patch-vhost-runtime.py" "${LIC_ROOT}" || true
fi

for old in 16 128; do
  if grep -q "#define HTTPD_MAX_ROUTES ${old}" "$NET_C"; then
    sed -i "s/#define HTTPD_MAX_ROUTES ${old}/#define HTTPD_MAX_ROUTES 256/" "$NET_C"
  fi
done

# Multi-route edge: disable proxy snap + upstream fd reuse; reset global resp cache per request.
sed -i 's/if (g_proxy_snap_ready || g_proxy_snap_recording || slot/if (httpd_proxy_snap_disabled() || g_proxy_snap_ready || g_proxy_snap_recording || slot/' "$NET_C" || true
sed -i 's/return g_proxy_snap_ready ? 1 : 0;/return (g_proxy_snap_ready \&\& !httpd_proxy_snap_disabled()) ? 1 : 0;/' "$NET_C" || true
sed -i 's/s->proxy_up_reuse = resp_keep;/s->proxy_up_reuse = 0;/' "$NET_C" || true
sed -i 's/s->proxy_up_reuse = 1;/s->proxy_up_reuse = 0;/g' "$NET_C" || true
python3 - "$NET_C" <<'PY' || true
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text()
needle = """  httpd_slot_t* s = &g_slots[slot];
  s->proxy_active = 1;"""
repl = """  httpd_slot_t* s = &g_slots[slot];
  g_proxy_resp_cl_cached = -1;
  g_proxy_resp_hdr_bytes_cached = 0;
  httpd_proxy_snap_reset();
  s->proxy_active = 1;"""
if needle in text and "g_proxy_resp_cl_cached = -1;" not in text.split("httpd_li_proxy_mark_active_i", 1)[-1][:600]:
    p.write_text(text.replace(needle, repl, 1))
PY

( cd "$LIC_ROOT" && ./scripts/build-li-httpd.sh )
sudo install -m 0755 "${LIC_ROOT}/build/li-httpd" /usr/local/bin/li-httpd
echo "build-edge-li-httpd: installed /usr/local/bin/li-httpd"
