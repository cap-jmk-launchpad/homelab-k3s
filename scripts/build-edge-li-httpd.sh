#!/usr/bin/env bash
# Rebuild /usr/local/bin/li-httpd on blackpearl for multi-site vhost edge routing.
set -euo pipefail

if [[ -n "${SUDO_USER:-}" ]] && [[ "$(id -u)" -eq 0 ]]; then
  _home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  if [[ -n "$_home" ]]; then
    HOME="$_home"
    export HOME
  fi
fi

LIC_ROOT="${LIC_ROOT:-${HOME}/staging/lic}"
LI_HTTPD_ROOT="${LI_HTTPD_ROOT:-${HOME}/staging/li-httpd}"
NET_C="${LIC_ROOT}/runtime/li_rt_net.c"
BUILD_LI="${LIC_ROOT}/scripts/build-li-httpd.sh"

[[ -f "$NET_C" ]] || { echo "missing $NET_C" >&2; exit 1; }
[[ -f "$BUILD_LI" ]] || { echo "missing $BUILD_LI" >&2; exit 1; }

if [[ -f "${LI_HTTPD_ROOT}/scripts/patch-vhost-runtime.py" ]] \
  && [[ -d "${LIC_ROOT}/.git" ]] \
  && ! grep -q 'httpd_req_vhost_matches' "$NET_C"; then
  python3 "${LI_HTTPD_ROOT}/scripts/patch-vhost-runtime.py" "${LIC_ROOT}" || true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/apply-edge-tls-patch.sh" ]]; then
  bash "${SCRIPT_DIR}/apply-edge-tls-patch.sh"
fi
if [[ -f "${SCRIPT_DIR}/apply-edge-vhost-patch.sh" ]]; then
  bash "${SCRIPT_DIR}/apply-edge-vhost-patch.sh"
fi
if [[ -f "${SCRIPT_DIR}/apply-edge-proxy-patch.sh" ]]; then
  bash "${SCRIPT_DIR}/apply-edge-proxy-patch.sh"
fi

if grep -qE '^#define HTTPD_MAX_ROUTES ' "$NET_C"; then
  echo "build-edge-li-httpd: $NET_C still uses fixed HTTPD_MAX_ROUTES; upgrade lic for dynamic route table" >&2
  exit 1
fi
if ! grep -q 'httpd_proxy_snap_disabled' "$NET_C"; then
  echo "build-edge-li-httpd: lic missing httpd_proxy_snap_disabled; upgrade lic before edge build" >&2
  exit 1
fi
echo "build-edge-li-httpd: skipping legacy sed patches (edge proxy fixes are in lic)"
( cd "$LIC_ROOT" && ./scripts/build-li-httpd.sh )
sudo install -m 0755 "${LIC_ROOT}/build/li-httpd" /usr/local/bin/li-httpd
echo "build-edge-li-httpd: installed /usr/local/bin/li-httpd"
