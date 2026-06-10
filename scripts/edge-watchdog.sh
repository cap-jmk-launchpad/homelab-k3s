#!/usr/bin/env bash
# blackpearl edge watchdog — GitLab prod HTTPS via nginx :443; heal nginx + li-httpd HTTP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY="${EDGE_LIS_APPLY:-${SCRIPT_DIR}/edge-lis-apply.sh}"
NGINX_APPLY="${EDGE_NGINX_APPLY:-${SCRIPT_DIR}/edge-nginx-apply.sh}"
if [[ ! -f "$APPLY" ]]; then
  APPLY="/home/s4il0r/staging/homelab-k3s/scripts/edge-lis-apply.sh"
fi
if [[ ! -f "$NGINX_APPLY" ]]; then
  NGINX_APPLY="/home/s4il0r/staging/homelab-k3s/scripts/edge-nginx-apply.sh"
fi
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
  local -a args=( -s -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 20 -k )
  if [[ -n "$resolve" ]]; then
    args+=( --resolve "$resolve" )
  fi
  local code=""
  code=$(curl "${args[@]}" "$url" 2>/dev/null) || true
  if [[ -n "$code" ]]; then
    echo "$code"
  else
    echo "000"
  fi
}

if ! systemctl is-active --quiet nginx-gitlab-edge.service 2>/dev/null \
  || ! systemctl is-active --quiet li-httpd-homelab.service 2>/dev/null; then
  log "nginx-gitlab-edge or li-httpd HTTP inactive — apply + restart"
  bash "$NGINX_APPLY" --install-systemd 2>/dev/null || bash "$NGINX_APPLY" || true
  bash "$APPLY" --no-reload || true
  systemctl restart nginx-gitlab-edge.service 2>/dev/null || true
  systemctl restart li-httpd-homelab.service
  write_streak 0
  exit 0
fi

local="$(http_code "$LOCAL_URL" "$LOCAL_RESOLVE")"
wan="$(http_code "$WAN_URL")"

if [[ "$local" == "200" || "$local" == "302" || "$local" == "307" ]]; then
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

log "local failed ${FAIL_THRESHOLD}x — nginx + li-httpd HTTP heal"
bash "$APPLY" --no-reload
bash "$NGINX_APPLY" --no-reload 2>/dev/null || true
systemctl restart li-httpd-homelab.service
sleep 2
systemctl restart nginx-gitlab-edge.service
write_streak 0

sleep 3
local2="$(http_code "$LOCAL_URL" "$LOCAL_RESOLVE")"
log "after heal local=${local2}"
