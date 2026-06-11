#!/usr/bin/env bash
# blackpearl GitLab edge watchdog - probe nginx :443, heal upstream NodePort (engine DHCP),
# restart gitlab-0 if needed, optional reverse-tunnel fallback.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HOST="${GITLAB_WATCHDOG_HOST:-gitlab.lilangverse.xyz}"
PATH_PROBE="${GITLAB_WATCHDOG_PATH:-/users/sign_in}"
NGINX_CONF="${GITLAB_WATCHDOG_NGINX_CONF:-/etc/nginx/gitlab-edge/nginx.conf}"
NODEPORT="${GITLAB_NODEPORT:-30481}"
TUNNEL_PORT="${GITLAB_TUNNEL_PORT:-30581}"
ENGINE_NODE="${GITLAB_ENGINE_NODE:-engine}"
NAMESPACE="${GITLAB_NAMESPACE:-gitlab}"
POD_NAME="${GITLAB_POD:-gitlab-0}"

FAIL_STREAK_FILE="${GITLAB_WATCHDOG_FAIL_FILE:-/run/gitlab-edge-watchdog/fail-streak}"
FAIL_THRESHOLD="${GITLAB_WATCHDOG_FAIL_THRESHOLD:-2}"
LOG_TAG="gitlab-edge-watchdog"
LOG_FILE="${GITLAB_WATCHDOG_LOG:-/var/log/gitlab-edge-watchdog.log}"

KUBECTL="${KUBECTL:-kubectl}"
TUNNEL_RECOVERY="${GITLAB_TUNNEL_RECOVERY:-${SCRIPT_DIR}/gitlab-engine-tunnel-recovery.sh}"
ENABLE_TUNNEL_FALLBACK="${GITLAB_ENABLE_TUNNEL_FALLBACK:-1}"

log() {
  local msg="${LOG_TAG}: $*"
  echo "$msg"
  if [[ -w "$(dirname "$LOG_FILE")" ]] 2>/dev/null || [[ -w "$LOG_FILE" ]] 2>/dev/null; then
    printf '%s %s\n' "$(date -Is)" "$msg" >>"$LOG_FILE" 2>/dev/null || true
  fi
}

read_streak() {
  if [[ -f "$FAIL_STREAK_FILE" ]]; then
    tr -dc '0-9' <"$FAIL_STREAK_FILE" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

write_streak() {
  mkdir -p "$(dirname "$FAIL_STREAK_FILE")"
  printf '%s\n' "$1" >"$FAIL_STREAK_FILE"
}

http_code_nodeport() {
  local target="$1"
  local code=""
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 \
    -H "Host: ${HOST}" "http://${target}:${NODEPORT}${PATH_PROBE}" 2>/dev/null) || true
  [[ -n "$code" ]] && echo "$code" || echo "000"
}

http_code_nginx_local() {
  local code=""
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 25 -k \
    --resolve "${HOST}:443:127.0.0.1" "https://${HOST}${PATH_PROBE}" 2>/dev/null) || true
  [[ -n "$code" ]] && echo "$code" || echo "000"
}

ok_code() {
  case "$1" in
    200|302|307) return 0 ;;
    *) return 1 ;;
  esac
}

engine_internal_ip() {
  local ip=""
  ip="$("$KUBECTL" get node "$ENGINE_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)" || true
  echo "$ip"
}

current_upstream_host() {
  if [[ ! -f "$NGINX_CONF" ]]; then
    echo ""
    return
  fi
  grep -E "^[[:space:]]*server[[:space:]]+" "$NGINX_CONF" | head -1 | sed -E "s/^[[:space:]]*server[[:space:]]+([^:;]+):${NODEPORT};.*/\1/"
}

set_nginx_upstream() {
  local host="$1"
  local conf="$NGINX_CONF"
  local tmp
  tmp="$(mktemp)"
  if [[ ! -f "$conf" ]]; then
    log "nginx conf missing: $conf"
    return 1
  fi
  if grep -qE "server[[:space:]]+${host}:${NODEPORT};" "$conf"; then
    log "upstream already ${host}:${NODEPORT}"
    return 0
  fi
  sed -E "s/(server[[:space:]]+)[^:;]+:${NODEPORT};/\1${host}:${NODEPORT};/" "$conf" >"$tmp"
  install -m 644 "$tmp" "$conf"
  rm -f "$tmp"
  if command -v nginx >/dev/null 2>&1; then
    nginx -t -c "$conf"
    systemctl reload nginx-gitlab-edge.service 2>/dev/null || systemctl restart nginx-gitlab-edge.service
  fi
  log "patched nginx upstream -> ${host}:${NODEPORT}"
}

pick_working_nodeport_target() {
  local engine_ip="$1"
  local -a candidates=("127.0.0.1")
  if [[ -n "$engine_ip" ]]; then
    candidates+=("$engine_ip")
  fi
  local c code
  for c in "${candidates[@]}"; do
    code="$(http_code_nodeport "$c")"
    log "probe nodeport ${c}:${NODEPORT} -> ${code}"
    if ok_code "$code"; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

restart_gitlab_pod_if_unhealthy() {
  local phase ready
  phase="$("$KUBECTL" get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null)" || phase=""
  ready="$("$KUBECTL" get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" || ready=""
  if [[ "$phase" != "Running" || "$ready" != "True" ]]; then
    log "gitlab pod unhealthy phase=${phase} ready=${ready} - deleting ${POD_NAME}"
    "$KUBECTL" delete pod -n "$NAMESPACE" "$POD_NAME" --wait=false 2>/dev/null || true
    return 0
  fi
  log "gitlab pod phase=${phase} ready=${ready} (no restart)"
  return 1
}

maybe_tunnel_fallback() {
  if [[ "$ENABLE_TUNNEL_FALLBACK" != "1" ]]; then
    log "tunnel fallback disabled"
    return 1
  fi
  if [[ ! -f "$TUNNEL_RECOVERY" ]]; then
    log "tunnel recovery script missing: $TUNNEL_RECOVERY"
    return 1
  fi
  log "starting reverse-tunnel fallback (${TUNNEL_PORT})"
  bash "$TUNNEL_RECOVERY" || log "tunnel recovery exited non-zero"
  return 0
}

heal_sequence() {
  local engine_ip target local_code
  engine_ip="$(engine_internal_ip)"
  log "engine InternalIP=${engine_ip:-unknown}"

  if target="$(pick_working_nodeport_target "$engine_ip")"; then
    set_nginx_upstream "$target" || true
    sleep 2
    local_code="$(http_code_nginx_local)"
    if ok_code "$local_code"; then
      log "heal OK after upstream ${target} local=${local_code}"
      return 0
    fi
    log "nginx still bad after upstream patch local=${local_code}"
  else
    log "no working NodePort target on 127.0.0.1 or engine IP"
  fi

  if [[ -n "$engine_ip" ]] && ok_code "$(http_code_nodeport "$engine_ip")"; then
    restart_gitlab_pod_if_unhealthy || true
    sleep 30
    if target="$(pick_working_nodeport_target "$engine_ip")"; then
      set_nginx_upstream "$target" || true
      sleep 2
      local_code="$(http_code_nginx_local)"
      if ok_code "$local_code"; then
        log "heal OK after pod recycle local=${local_code}"
        return 0
      fi
    fi
  fi

  maybe_tunnel_fallback
  sleep 5
  local_code="$(http_code_nginx_local)"
  log "after tunnel fallback local=${local_code}"
  ok_code "$local_code"
}

mkdir -p "$(dirname "$FAIL_STREAK_FILE")" 2>/dev/null || true

if ! systemctl is-active --quiet nginx-gitlab-edge.service 2>/dev/null; then
  log "nginx-gitlab-edge inactive - restart"
  systemctl restart nginx-gitlab-edge.service 2>/dev/null || true
  write_streak 0
  exit 0
fi

local="$(http_code_nginx_local)"
if ok_code "$local"; then
  write_streak 0
  cur="$(current_upstream_host)"
  if [[ -n "$cur" && "$cur" != "127.0.0.1" ]] && ok_code "$(http_code_nodeport "127.0.0.1")"; then
    log "OK local=${local}; normalizing upstream 127.0.0.1 (was ${cur})"
    set_nginx_upstream "127.0.0.1" || true
  else
    log "OK local=${local} upstream=${cur:-?}"
  fi
  exit 0
fi

streak="$(read_streak)"
streak=$((streak + 1))
write_streak "$streak"
log "FAIL local=${local} streak=${streak}/${FAIL_THRESHOLD}"

if [[ "$streak" -lt "$FAIL_THRESHOLD" ]]; then
  exit 0
fi

if heal_sequence; then
  write_streak 0
  exit 0
fi

write_streak "$streak"
exit 1