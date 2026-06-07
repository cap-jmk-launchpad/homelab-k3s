#!/usr/bin/env bash
# Rebuild /usr/local/bin/li-httpd on blackpearl for multi-site vhost edge routing.
set -euo pipefail

LIC_ROOT="${LIC_ROOT:-${HOME}/staging/lic}"
LI_HTTPD_ROOT="${LI_HTTPD_ROOT:-${HOME}/staging/li-httpd}"
BUILD="${BUILD:-${HOME}/staging/majico-deploy/deploy/staging/scripts/build-li-httpd.sh}"
NET_C="${LIC_ROOT}/runtime/li_rt_net.c"

[[ -f "$NET_C" ]] || { echo "missing $NET_C" >&2; exit 1; }
[[ -f "$BUILD" ]] || { echo "missing $BUILD" >&2; exit 1; }

if [[ -f "${LI_HTTPD_ROOT}/scripts/patch-vhost-runtime.py" ]] \
  && [[ -d "${LIC_ROOT}/.git" ]]; then
  python3 "${LI_HTTPD_ROOT}/scripts/patch-vhost-runtime.py" "${LIC_ROOT}" || true
fi

for old in 16 128; do
  if grep -q "#define HTTPD_MAX_ROUTES ${old}" "$NET_C"; then
    sed -i "s/#define HTTPD_MAX_ROUTES ${old}/#define HTTPD_MAX_ROUTES 256/" "$NET_C"
  fi
done

LIC_ROOT="$(cd "$LIC_ROOT" && pwd)" bash "$BUILD"
echo "build-edge-li-httpd: installed $(command -v li-httpd)"
