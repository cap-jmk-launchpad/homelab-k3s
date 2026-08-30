#!/usr/bin/env bash
# cluster-watchdog.sh — unified cluster watchdog for the homelab k3s cluster.
#
# Runs as a single systemd timer on blackpearl (the edge + control-plane node that
# owns li-httpd/nginx, the kubeconfig, and SSH access to the workers). It consolidates
# the previously-overlapping watchdogs (edge-watchdog.sh + gitlab-edge-watchdog.sh) and
# the scattered per-stack backup-prune CronJobs into ONE keep-up loop:
#
#   1. keep_portfolio_up   — probe portfolio (127.0.0.1:30585 + WAN julianmkleber.com);
#                            restart the backend pod if down; re-apply edge config/cert.
#   2. prune_stale         — delete Failed/Succeeded/Evicted pods, completed Jobs, and
#                            Released local-path PVs to reclaim disk (every run).
#   3. rotate_backups      — daily: rotate gitlab backups (exec gitlab-0) + trigger the
#                            per-stack backup-prune CronJobs (supabase family).
#   4. check_services      — probe every WAN/LAN service in services.conf; restart pods
#                            that are down, EXCEPT agent-swarm (monitor-only).
#   5. heal_edge           — keep li-httpd (:80) + nginx (:443) alive; re-apply configs;
#                            heal the GitLab nginx upstream for engine's DHCP IP.
#
# --check-only runs every probe but performs NO mutations (safe dry-run).
# Logs go to journalctl (ExecStart) and /var/log/cluster-watchdog.log (best-effort).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Honour REPO_ROOT from the environment (systemd unit sets it to the checkout);
# fall back to the script's own location for local/ad-hoc runs.
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
LOG_TAG="cluster-watchdog"
LOG_FILE="${CLUSTER_WATCHDOG_LOG:-/var/log/cluster-watchdog.log}"

KUBECONFIG="${KUBECONFIG:-/home/s4il0r/.kube/config}"
export KUBECONFIG
K="${KUBECTL:-kubectl}"

PROBE_TIMEOUT="${PROBE_TIMEOUT:-10}"
PROBE_MAX="${PROBE_MAX:-15}"
HEALTH_STREAK_DIR="${HEALTH_STREAK_DIR:-/run/cluster-watchdog}"
IMAGE_PRUNE_HOURS="${IMAGE_PRUNE_HOURS:-6}"
BACKUP_ROTATE_HOURS="${BACKUP_ROTATE_HOURS:-24}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
ENGINE_NODE="${ENGINE_NODE:-engine}"
PORTFOLIO_FAIL_THRESHOLD="${PORTFOLIO_FAIL_THRESHOLD:-2}"
SVC_FAIL_THRESHOLD="${SVC_FAIL_THRESHOLD:-2}"
# Namespaces the watchdog must NEVER restart or prune (e.g. the li-langverse agent
# swarm, which has its own lifecycle). Set WATCHDOG_SKIP_NAMESPACES to override.
WATCHDOG_SKIP_NS="${WATCHDOG_SKIP_NAMESPACES:-agent-swarm}"

mkdir -p "$HEALTH_STREAK_DIR" 2>/dev/null || true

CHECK_ONLY=0

log() { local msg="$*"; local ts; ts=$(date -Is 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'); printf '%s %s: %s\n' "$ts" "$LOG_TAG" "$msg" | tee -a "$LOG_FILE" 2>/dev/null || printf '%s %s: %s\n' "$ts" "$LOG_TAG" "$msg"; }

# Run a mutating command unless --check-only was given (then just log the intent).
mut() { if [[ "$CHECK_ONLY" -ne 1 ]]; then "$@"; else log "[dry-run] would: $*"; fi; }

# http_code_url URL [resolve_host]  -> prints HTTP code (000 on failure)
http_code_url() {
  local url="$1" resolve="${2:-}" code=""
  local -a args=(-s -o /dev/null -w '%{http_code}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX")
  if [[ -n "$resolve" ]]; then args+=(--resolve "$resolve"); fi
  code=$(curl "${args[@]}" "$url" 2>/dev/null) || true
  [[ -n "$code" ]] && echo "$code" || echo "000"
}

# http_code_nodeport PORT [PATH]  -> 127.0.0.1:PORT/PATH
http_code_nodeport() {
  local port="$1" path="${2:-/}"
  [[ -z "$path" ]] && path="/"
  [[ "$path" != /* ]] && path="/$path"
  http_code_url "http://127.0.0.1:${port}${path}"
}

ok_code() { case "$1" in 2[0-9][0-9]|3[0-9][0-9]) return 0 ;; *) return 1 ;; esac; }

streak_file() { echo "${HEALTH_STREAK_DIR}/$1.fail-streak"; }
read_streak() { [[ -f "$1" ]] && tr -dc '0-9' <"$1" 2>/dev/null || echo 0; }
write_streak() { mkdir -p "$(dirname "$1")" 2>/dev/null || true; printf '%s\n' "$2" >"$1" 2>/dev/null || true; }

# --- engine DHCP IP (flips 192.168.10.32 <-> .40 between links) ---
engine_internal_ip() { "$K" get node "$ENGINE_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true; }
node_ip() { "$K" get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true; }

# Resolve a containerd CLI (k3s nodes ship `k3s ctr`; bare `ctr` also works).
ctr_sock() { echo "${CONTAINERD_SOCKET:-/run/k3s/containerd/containerd.sock}"; }
ctr_cli() {
  if command -v k3s >/dev/null 2>&1; then echo "k3s ctr --address $(ctr_sock)"
  elif command -v ctr >/dev/null 2>&1; then echo "ctr --address $(ctr_sock)"
  else echo ""; fi
}
ctr_prune() { local cli; cli=$(ctr_cli); [[ -n "$cli" ]] || { log "prune: no containerd CLI (k3s/ctr) on this host"; return 0; }; eval "$cli images prune" 2>/dev/null || true; eval "$cli content prune" 2>/dev/null || true; }

# ssh_node_rm NODENAME PATH — best-effort remote rm (for local-path host dirs on engine)
ssh_node_rm() {
  local node="$1" path="$2" ip
  ip=$(node_ip "$node") || return 0
  [[ -n "$ip" ]] || return 0
  ssh -i "${SSH_KEY:-/home/s4il0r/.ssh/homelab}" -o BatchMode=yes -o StrictHostKeyChecking=no \
     -o ConnectTimeout=5 "s4il0r@${ip}" "sudo rm -rf ${path}" 2>/dev/null || true
}

EDGE_LIS_APPLY="${REPO_ROOT}/scripts/edge-lis-apply.sh"
EDGE_NGINX_APPLY="${REPO_ROOT}/scripts/edge-nginx-apply.sh"
GITLAB_EDGE_WATCHDOG="${REPO_ROOT}/scripts/gitlab-edge-watchdog.sh"
PORTFOLIO_HEALER="${REPO_ROOT}/scripts/homelab-edge-policy-check.sh"
PORTFOLIO_CERTBOT="${REPO_ROOT}/scripts/edge-julianmkleber-certbot.sh"
INVENTORY="${CLUSTER_WATCHDOG_INVENTORY:-${REPO_ROOT}/k8s/monitoring/cluster-watchdog/services.conf}"

# find_port_owner PORT [namespace_hint] -> echoes "ns selector" for the Service with nodePort=PORT
find_port_owner() {
  local port="$1" hint="${2:-}"
  local namespaces ns
  if [[ -n "$hint" ]]; then namespaces="$hint"
  else namespaces="$("$K" get ns -o name 2>/dev/null | sed 's|^namespace/||')"; fi
  for ns in $namespaces; do
    local svcs; svcs=$("$K" get svc -n "$ns" -o name 2>/dev/null) || continue
    local s
    for s in $svcs; do
      local nps; nps=$("$K" get "$s" -n "$ns" -o jsonpath='{.spec.ports[*].nodePort}' 2>/dev/null) || continue
      if echo "$nps" | grep -qw "$port"; then
        local sel; sel=$("$K" get "$s" -n "$ns" -o go-template='{{range $k,$v := .spec.selector}}{{$k}}={{$v}},{{end}}' 2>/dev/null)
        sel="${sel%,}"
        echo "$ns $sel"
        return 0
      fi
    done
  done
  return 1
}

# restart_pods_for_nodeport PORT [namespace_hint]
restart_pods_for_nodeport() {
  local port="$1" hint="${2:-}" owner
  if ! owner=$(find_port_owner "$port" "$hint"); then
    log "restart: no Service with nodePort ${port} found — cannot restart backend"
    return 1
  fi
  local ns sel; read -r ns sel <<<"$owner"
  log "restart: nodePort ${port} -> ns=${ns} selector='${sel:-<all>}'"
  mut "$K" delete pod -n "$ns" -l "$sel" --wait=false 2>/dev/null || true
  sleep 8
  local code; code=$(http_code_nodeport "$port" "/")
  if ok_code "$code"; then log "restart: nodePort ${port} recovered (code=${code})"; else log "restart: nodePort ${port} STILL DOWN (code=${code}) after pod recycle"; fi
}

# --- 1. keep_portfolio_up ---
keep_portfolio_up() {
  local streakf; streakf=$(streak_file portfolio)
  local backend_code wan_code
  backend_code=$(http_code_nodeport 30585 "")
  wan_code=$(http_code_url "https://www.julianmkleber.com/health" "www.julianmkleber.com:443:127.0.0.1")
  log "portfolio: backend=127.0.0.1:30585 code=${backend_code} wan=${wan_code}"

  if ok_code "$backend_code"; then
    if ! ok_code "$wan_code"; then
      log "portfolio: backend OK but WAN https://www.julianmkleber.com/health fails -> re-apply edge"
      mut bash "$PORTFOLIO_HEALER" --fix 2>/dev/null || true
      mut bash "$EDGE_NGINX_APPLY" --no-reload 2>/dev/null || true
      [[ -x "$PORTFOLIO_CERTBOT" ]] && mut bash "$PORTFOLIO_CERTBOT" 2>/dev/null || true
      mut systemctl reload nginx-gitlab-edge.service 2>/dev/null || mut systemctl restart nginx-gitlab-edge.service 2>/dev/null || true
      write_streak "$streakf" 0
      return 0
    fi
    write_streak "$streakf" 0
    log "portfolio: OK"
    return 0
  fi

  local streak; streak=$(read_streak "$streakf"); streak=$((streak + 1)); write_streak "$streakf" "$streak"
  log "portfolio: backend DOWN streak=${streak}"
  if [[ "$streak" -lt "$PORTFOLIO_FAIL_THRESHOLD" ]]; then return 0; fi
  mut restart_pods_for_nodeport 30585 ""
  write_streak "$streakf" 0
}

# skip_ns REF -> 0 if the namespace of REF (e.g. "pod/ns/name" or bare "ns") must be
# left untouched, else 1. REF may be a pod name, job ref, or plain namespace.
skip_ns() {
  local ref="$1" ns
  if [[ "$ref" == pod/* ]]; then ns="${ref#pod/}"; ns="${ns%%/*}"
  elif [[ "$ref" == job/* ]]; then ns="${ref#job/}"; ns="${ns%%/*}"
  else ns="$ref"; fi
  case " $WATCHDOG_SKIP_NS " in *" $ns "*) return 0 ;; esac
  return 1
}

# --- 1b. keep_librebase_staging_up (stage.librebase.xyz landing + app-stage app/MCP) ---
# Staging is served by the nginx :443 edge via nginx-librebase-staging.conf; if a vhost
# is dropped (e.g. after a re-apply from a repo without the file) or the upstream stops
# answering, re-apply the edge config and reload nginx. The docker stack itself is
# managed by the staging deploy webhook / auto-deploy cron on engine, not here.
keep_librebase_staging_up() {
  local streakf; streakf=$(streak_file librebase-staging)
  local stage_code app_code
  stage_code=$(http_code_url "https://stage.librebase.xyz/api/admin-proxy/health" "stage.librebase.xyz:443:127.0.0.1")
  app_code=$(http_code_url "https://app-stage.librebase.xyz/api/admin-proxy/health" "app-stage.librebase.xyz:443:127.0.0.1")
  log "librebase-staging: stage=${stage_code} app-stage=${app_code}"

  if ok_code "$stage_code" && ok_code "$app_code"; then
    write_streak "$streakf" 0
    log "librebase-staging: OK"
    return 0
  fi

  local streak; streak=$(read_streak "$streakf"); streak=$((streak + 1)); write_streak "$streakf" "$streak"
  log "librebase-staging: DEGRADED stage=${stage_code} app-stage=${app_code} streak=${streak}/${LIBREBASE_STAGING_HEAL_THRESHOLD:-2}"
  if [[ "$streak" -lt "${LIBREBASE_STAGING_HEAL_THRESHOLD:-2}" ]]; then return 0; fi

  log "librebase-staging: threshold reached — re-apply edge config + reload nginx"
  mut bash "$EDGE_NGINX_APPLY" --no-reload 2>/dev/null || true
  mut systemctl reload nginx-gitlab-edge.service 2>/dev/null || mut systemctl restart nginx-gitlab-edge.service 2>/dev/null || true
  write_streak "$streakf" 0
}

# --- 2. prune_stale (disk reclaim; every run, cheap) ---
prune_stale() {
  log "prune: collecting stale pods/jobs/pvs (skip-ns=[${WATCHDOG_SKIP_NS}])"
  local p
  "$K" get pods -A --field-selector=status.phase=Failed -o name 2>/dev/null | while read -r p; do
    skip_ns "$p" && continue
    log "prune: delete Failed pod $p"; mut "$K" delete pod "$p" --force=false --ignore-not-found 2>/dev/null || true
  done
  "$K" get pods -A --field-selector=status.phase=Succeeded -o name 2>/dev/null | while read -r p; do
    skip_ns "$p" && continue
    log "prune: delete Succeeded pod $p"; mut "$K" delete pod "$p" --force=false --ignore-not-found 2>/dev/null || true
  done
  "$K" get pods -A --field-selector=status.reason=Evicted -o name 2>/dev/null | while read -r p; do
    skip_ns "$p" && continue
    log "prune: delete Evicted pod $p"; mut "$K" delete pod "$p" --ignore-not-found 2>/dev/null || true
  done
  # Completed Jobs older than retention
  local cutoff; cutoff=$(date -u -d "-${BACKUP_RETENTION_DAYS} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-${BACKUP_RETENTION_DAYS}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)
  if [[ -n "$cutoff" ]]; then
    "$K" get jobs -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,COMP:.status.completionTime --no-headers 2>/dev/null | while read -r ns name comp; do
      [[ -n "$comp" ]] || continue
      skip_ns "$ns" && continue
      if [[ "$comp" < "$cutoff" ]]; then log "prune: delete stale Job ${ns}/${name} completed ${comp}"; mut "$K" delete job -n "$ns" "$name" --ignore-not-found 2>/dev/null || true; fi
    done
  fi
  # Released local-path PVs (delete object + clean host dir on engine)
  "$K" get pv -o name --field-selector=status.phase=Released 2>/dev/null | while read -r pv; do
    log "prune: delete Released PV $pv"; mut "$K" delete "$pv" --ignore-not-found 2>/dev/null || true
    local pname="${pv#persistentvolume/}"
    mut ssh_node_rm "engine" "/var/lib/rancher/k3s/storage/${pname}" 2>/dev/null || true
  done
}

# --- 2b. containerd image prune (gated; real image-layer GC) ---
prune_images_gated() {
  local stamp="${HEALTH_STREAK_DIR}/images-pruned"; local last=0
  [[ -f "$stamp" ]] && last=$(tr -dc '0-9' <"$stamp" 2>/dev/null || echo 0)
  local now; now=$(date +%s)
  if (( now - last < IMAGE_PRUNE_HOURS * 3600 )); then return 0; fi
  log "prune: containerd image GC (nodes: blackpearl + engine)"
  mut ctr_prune
  log "prune: blackpearl containerd images pruned"
  local eng; eng=$(node_ip "$ENGINE_NODE")
  if [[ -n "$eng" ]]; then
    mut ssh -i "${SSH_KEY:-/home/s4il0r/.ssh/homelab}" -o BatchMode=yes -o StrictHostKeyChecking=no \
       -o ConnectTimeout=8 "s4il0r@${eng}" "sudo k3s ctr --address /run/k3s/containerd/containerd.sock images prune 2>/dev/null; sudo k3s ctr --address /run/k3s/containerd/containerd.sock content prune 2>/dev/null" 2>/dev/null && log "prune: engine containerd images pruned" || log "prune: engine image prune skipped (ssh/ctr unavailable)"
  fi
  if [[ "$CHECK_ONLY" -ne 1 ]]; then date +%s >"$stamp" 2>/dev/null || true; fi
}

# --- 3. rotate_backups (gated daily) ---
rotate_backups() {
  local stamp="${HEALTH_STREAK_DIR}/backups-rotated"; local last=0
  [[ -f "$stamp" ]] && last=$(tr -dc '0-9' <"$stamp" 2>/dev/null || echo 0)
  local now; now=$(date +%s)
  if (( now - last < BACKUP_ROTATE_HOURS * 3600 )); then return 0; fi
  log "rotate: pruning old backups (retention=${BACKUP_RETENTION_DAYS}d)"
  # GitLab Omnibus backups (no rotation existed before -> added here)
  if "$K" get pod -n gitlab -l app=gitlab --field-selector=status.phase=Running -o name 2>/dev/null | grep -q .; then
    local gpod; gpod=$("$K" get pod -n gitlab -l app=gitlab -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    mut "$K" exec -n gitlab "$gpod" -- find /var/opt/gitlab/backups -name '*_gitlab_backup.tar' -mtime +"$BACKUP_RETENTION_DAYS" -delete 2>/dev/null \
      && log "rotate: gitlab backups older than ${BACKUP_RETENTION_DAYS}d pruned" || log "rotate: gitlab backup prune failed/skipped"
  else
    log "rotate: no running gitlab pod — skipping gitlab backup rotation"
  fi
  # Supabase-family backups: reuse the per-stack backup-prune CronJobs on-demand
  for cj in supabase/supabase-backup-prune librebase-supabase/librebase-supabase-backup-prune agentic-book-supabase/agentic-book-supabase-backup-prune; do
    local ns="${cj%/*}" name="${cj#*/}" ts="rotate-$(date -u +%Y%m%d%H%M%S)"
    if "$K" get cronjob -n "$ns" "$name" >/dev/null 2>&1; then
      mut "$K" create job -n "$ns" "${ts}" --from="cronjob/${name}" 2>/dev/null \
        && log "rotate: triggered $ns/$name" || log "rotate: $name not triggered in $ns (skipped)"
    else
      log "rotate: cronjob $ns/$name not present (skipped)"
    fi
  done
  if [[ "$CHECK_ONLY" -ne 1 ]]; then date +%s >"$stamp" 2>/dev/null || true; fi
}

# --- 4. check_services (probe inventory; restart down, non-agent-swarm pods) ---
check_services() {
  [[ -f "$INVENTORY" ]] || { log "check_services: inventory $INVENTORY missing"; return 0; }
  local name port path restart hint code line
  while IFS= read -r line; do
    case "$line" in \#*|'') continue ;; esac
    IFS=':' read -r name port path restart hint <<<"$line"
    [[ -z "$port" ]] && continue
    code=$(http_code_nodeport "$port" "$path")
    if ok_code "$code"; then
      log "service ${name} (${port}): UP (code=${code})"
      continue
    fi
    if [[ "$restart" == "1" ]]; then
      log "service ${name} (${port}): DOWN (code=${code}) — monitor-only (restart=1, no recycle)"
      continue
    fi
    local sf; sf=$(streak_file "svc-${name}"); local streak; streak=$(read_streak "$sf"); streak=$((streak + 1)); write_streak "$sf" "$streak"
    log "service ${name} (${port}): DOWN (code=${code}) streak=${streak}"
    if [[ "$streak" -ge "$SVC_FAIL_THRESHOLD" ]]; then
      mut restart_pods_for_nodeport "$port" "$hint"
      write_streak "$sf" 0
    fi
  done <"$INVENTORY"
}

# --- 5. heal_edge (li-httpd :80 + nginx :443; GitLab upstream + pod) ---
# Replaces edge-watchdog.sh: restarts li-httpd/nginx if the systemd unit is inactive
# or the public probe fails repeatedly (streak gate avoids config-reapply flapping).
heal_edge() {
  local li_code nginx_code nodeport_code streakf
  streakf=$(streak_file heal-edge)
  li_code=$(http_code_url "http://gitlab.lilangverse.xyz/health" "gitlab.lilangverse.xyz:80:127.0.0.1")
  nginx_code=$(http_code_url "https://gitlab.lilangverse.xyz/users/sign_in" "gitlab.lilangverse.xyz:443:127.0.0.1")
  nodeport_code=$(http_code_nodeport 30481 "/users/sign_in")

  # Fast path: units active and both probes healthy.
  if systemctl is-active --quiet li-httpd-homelab.service 2>/dev/null \
     && systemctl is-active --quiet nginx-gitlab-edge.service 2>/dev/null \
     && ok_code "$li_code" && ok_code "$nginx_code"; then
    log "edge: li-httpd=${li_code} nginx=${nginx_code} gitlab-nodeport=${nodeport_code} — OK"
    if [[ "$nodeport_code" == "000" ]] || ! ok_code "$nodeport_code"; then
      log "edge: NodePort 30481 down while nginx up — delegate to gitlab-edge-watchdog (upstream + pod)"
      [[ -x "$GITLAB_EDGE_WATCHDOG" ]] && mut bash "$GITLAB_EDGE_WATCHDOG" || true
    fi
    write_streak "$streakf" 0
    return 0
  fi

  # Inactive unit or probe failure: streak-gate the heavier heal (reapply + restart).
  local streak; streak=$(read_streak "$streakf"); streak=$((streak + 1)); write_streak "$streakf" "$streak"
  log "edge: DEGRADED li-httpd=${li_code} nginx=${nginx_code} nodeport=${nodeport_code} streak=${streak}/${EDGE_HEAL_THRESHOLD:-2}"
  if [[ "$streak" -lt "${EDGE_HEAL_THRESHOLD:-2}" ]]; then
    # still let the gitlab-specific upstream/pod healer run on the first failure
    if [[ "$nginx_code" == "000" ]] || ! ok_code "$nginx_code"; then
      [[ -x "$GITLAB_EDGE_WATCHDOG" ]] && mut bash "$GITLAB_EDGE_WATCHDOG" || true
    fi
    return 0
  fi

  log "edge: threshold reached — re-apply li-httpd + nginx configs, restart units"
  mut bash "$EDGE_LIS_APPLY" --no-reload 2>/dev/null || true
  mut bash "$EDGE_NGINX_APPLY" --no-reload 2>/dev/null || true
  if ! systemctl is-active --quiet li-httpd-homelab.service 2>/dev/null; then
    mut systemctl restart li-httpd-homelab.service 2>/dev/null || true
  fi
  if ! systemctl is-active --quiet nginx-gitlab-edge.service 2>/dev/null; then
    mut systemctl restart nginx-gitlab-edge.service 2>/dev/null || true
  fi
  sleep 3
  local li2 ng2; li2=$(http_code_url "http://gitlab.lilangverse.xyz/health" "gitlab.lilangverse.xyz:80:127.0.0.1")
  ng2=$(http_code_url "https://gitlab.lilangverse.xyz/users/sign_in" "gitlab.lilangverse.xyz:443:127.0.0.1")
  log "edge: after heal li-httpd=${li2} nginx=${ng2}"
  [[ -x "$GITLAB_EDGE_WATCHDOG" ]] && mut bash "$GITLAB_EDGE_WATCHDOG" || true
  write_streak "$streakf" 0
}

usage() { cat <<EOF
Usage: $0 [--once | --check-only | --dry-run | --help]
  --once         run all phases once and exit (default for the systemd timer)
  --check-only   probe + report only; perform NO restarts/reloads/prunes (dry-run)
  --dry-run      alias for --check-only (safe, no mutations)
  --help         this help

Exit non-zero on an unknown arg: a watchdog that claims "no mutations" must
never silently fall through to a live run. Use --dry-run/--check-only for testing.
EOF
}

# Safety: unknown args must NOT silently fall through to a live run. The
# previous "WARN + continue" behavior turned a typo (e.g. --dry-run before it
# was an alias) into a real mutating run. Now we hard-fail so a dry-run that
# claims "no mutations" is guaranteed to perform no mutations.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) shift ;;
    --check-only|--dry-run) CHECK_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) log "ERROR: unknown arg: $1"; usage; exit 2 ;;
  esac
done
# Circuit-breaker: if /etc/cluster-watchdog/DISABLED exists, do not mutate.
# (Deactivation is normally done via `systemctl disable --now cluster-watchdog.timer`,
# but this file lets you hard-halt a run without touching systemd.)
if [[ -e /etc/cluster-watchdog/DISABLED ]]; then
  log "cluster-watchdog: DISABLED (/etc/cluster-watchdog/DISABLED present); exiting without mutations"
  exit 0
fi

log "=== cluster-watchdog run start (check_only=${CHECK_ONLY}) ==="
heal_edge
keep_portfolio_up
keep_librebase_staging_up
check_services
prune_stale
prune_images_gated
rotate_backups
log "=== cluster-watchdog run complete ==="
