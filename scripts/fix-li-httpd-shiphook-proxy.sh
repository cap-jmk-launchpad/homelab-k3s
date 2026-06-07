#!/usr/bin/env bash
# Rebuild li-httpd on blackpearl so named upstream_peer lines register (Shiphook :3141).
set -euo pipefail
NET="${LIC_ROOT:-$HOME/staging/lic}/runtime/li_rt_net.c"
BUILD="${HOME}/staging/majico-deploy/deploy/staging/scripts/build-li-httpd.sh"

[[ -f "$NET" ]] || { echo "missing $NET" >&2; exit 1; }
[[ -x "$BUILD" ]] || { echo "missing $BUILD — clone majico-deploy" >&2; exit 1; }

if grep -q 'httpd_add_upstream_peer_pool_i' "$NET"; then
  if ! grep -q 'g_proxy_port <= 0 && g_up_peer_count <= 0' "$NET"; then
    sed -i 's/if (g_proxy_port <= 0) {/if (g_proxy_port <= 0 \&\& g_up_peer_count <= 0) {/' "$NET"
    echo "patched path_proxy_match in $NET"
  fi
else
  echo "warn: no pool upstream parser — sync lic from li-langverse or copy li_rt_net.c" >&2
fi

LIC_ROOT="$(dirname "$(dirname "$NET")")" bash "$BUILD"
sudo systemctl restart li-httpd-homelab.service li-httpd-homelab-tls.service
systemctl is-active li-httpd-homelab.service li-httpd-homelab-tls.service shiphook-staging.service

SECRET="$(cat "$HOME/staging/shiphook-server/.shiphook.staging.secret")"
curl -sS -m 60 -N -X POST "http://127.0.0.1:80/deploy/staging" \
  -H "Host: majico.d3bu7.com" \
  -H "X-Shiphook-Secret: ${SECRET}" \
  -H "Content-Type: application/json" \
  -d '{"skipPull":true,"env":{"SKIP_BUILD":"true","SKIP_PUSH":"true"}}' \
  -w "\nHTTP:%{http_code}\n" | tail -6
