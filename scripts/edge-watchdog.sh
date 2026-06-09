#!/usr/bin/env bash
# blackpearl edge watchdog — verify GitLab WAN HTTPS and heal flapping li-httpd.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY="${SCRIPT_DIR}/edge-lis-apply.sh"
HOST="${EDGE_WATCHDOG_HOST:-gitlab.lilangverse.xyz}"
PATH_PROBE="${EDGE_WATCHDOG_PATH:-/users/sign_in}"
WAN_URL="https://${HOST}${PATH_PROBE}"
LOCAL_URL="https://${HOST}/users/sign_in"
LOG_TAG="edge-watchdog"

log() { echo "${LOG_TAG}: $*"; }

http_code() {
  local url="$1"
  local resolve="${2:-}"
  if command -v curl >/dev/null 2>&1; then
    if [[ -n "$resolve" ]]; then
      curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 20 \
        -k --resolve "$resolve" "$url" 2>/dev/null || echo "000"
    else
      curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 20 \
        -k "$url" 2>/dev/null || echo "000"
    fi
  else
    echo "000"
  fi
}

if ! systemctl is-active --quiet li-httpd-homelab.service 2>/dev/null \
  || ! systemctl is-active --quiet li-httpd-homelab-tls.service 2>/dev/null; then
  log "li-httpd unit inactive — render + restart"
  bash "$APPLY" --no-reload || true
  systemctl restart li-httpd-homelab.service
  systemctl restart li-httpd-homelab-tls.service
  exit 0
fi

wan="$(http_code "$WAN_URL")"
local="$(http_code "$LOCAL_URL" "${HOST}:443:127.0.0.1")"

if [[ "$wan" == "200" && "$local" == "200" ]]; then
  log "OK wan=${wan} local=${local}"
  exit 0
fi

log "FAIL wan=${wan} local=${local} — edge-lis-apply --no-reload + sequential restart"
bash "$APPLY" --no-reload
systemctl restart li-httpd-homelab.service
sleep 2
systemctl restart li-httpd-homelab-tls.service

sleep 3
wan2="$(http_code "$WAN_URL")"
log "after heal wan=${wan2}"
