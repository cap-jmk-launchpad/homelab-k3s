#!/usr/bin/env bash
set -euo pipefail
LIC_ROOT="${LIC_ROOT:-${HOME}/staging/lic}"
NET="${LIC_ROOT}/runtime/li_rt_net.c"
[[ -f "$NET" ]] || { echo "apply-edge-vhost-patch: missing $NET" >&2; exit 1; }
python3 - "$NET" <<'PY'
import sys
from pathlib import Path

net = Path(sys.argv[1])
text = net.read_text(encoding="utf-8").replace("\r\n", "\n")
orig = text
old = """    if (r->vhost[0] != '\\0' && host[0] != '\\0' && strcasecmp(r->vhost, host) != 0) {
      continue;
    }"""
new = """    if (r->vhost[0] != '\\0') {
      if (host[0] == '\\0' || strcasecmp(r->vhost, host) != 0) {
        continue;
      }
    }"""
if old in text:
    text = text.replace(old, new, 1)
marker = "if (host[0] == '\\0' || strcasecmp(r->vhost, host) != 0)"
if marker not in text and "httpd_req_vhost_matches" not in text:
    raise SystemExit("apply-edge-vhost-patch: expected vhost guard not found")
if text != orig:
    net.write_text(text, encoding="utf-8", newline="\n")
PY
echo "apply-edge-vhost-patch: ok"
