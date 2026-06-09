#!/usr/bin/env bash
# blackpearl edge watchdog — verify GitLab HTTPS on local li-httpd; heal only after repeated local failures.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY="${SCRIPT_DIR}/edge-lis-apply.sh"
HOST="${EDGE_WATCHDOG_HOST:-gitlab.lilangverse.xyz}"
PATH_PROBE="${EDGE_WATCHDOG_PATH:-/users/sign_in}"
LOCAL_RESOLVE="${HOST}:443:127.0.0.1"
LOCAL_URL="https://${HOST}${PATH_PROBE}"
WAN_URL="https://${HOST}${PATH_PROBE}"
FAIL_STREAK_FILE="${EDGE_WATCHDOG_FAIL_FILE:-/run/li-httpd/edge-watchdog-local-fail-streak}"
FAIL_THRESHOLD="${EDGE_WATCHDOG_FAIL_THRESHOLD:-3}"
LOG_TAG="edge-watchdog"

log() { echo "${LOG_TAG}: $*"; }

read_streak() {
  if [[ -f "$FAIL_STREAK_FILE" ]]; then
    tr -dc '0-9' <"$FAIL_STREAK_FILE" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

write_streak() {
  local n="$1"
  mkdir -p "$(dirname "$FAIL_STREAK_FILE")"
  printf '%s\n' "$n" >"$FAIL_STREAK_FILE"
}

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
  write_streak 0
  exit 0
fi

local="$(http_code "$LOCAL_URL" "$LOCAL_RESOLVE")"
wan="$(http_code "$WAN_URL")"

if [[ "$local" == "200" ]]; then
  write_streak 0
  if [[ "$wan" == "200" ]]; then
    log "OK local=${local} wan=${wan} (wan informational only)"
  else
    log "OK local=${local} wan=${wan} (wan fail ignored — hairpin/DNS; no restart)"
  fi
  exit 0
fi

streak="$(read_streak)"
streak=$((streak + 1))
write_streak "$streak"
log "local probe FAIL code=${local} streak=${streak}/${FAIL_THRESHOLD} wan=${wan} (wan not used for heal)"

if [[ "$streak" -lt "$FAIL_THRESHOLD" ]]; then
  exit 0
fi

log "local failed ${FAIL_THRESHOLD}x — edge-lis-apply --no-reload + sequential restart"
bash "$APPLY" --no-reload
systemctl restart li-httpd-homelab.service
sleep 2
systemctl restart li-httpd-homelab-tls.service
write_streak 0

sleep 3
local2="$(http_code "$LOCAL_URL" "$LOCAL_RESOLVE")"
log "after heal local=${local2}"