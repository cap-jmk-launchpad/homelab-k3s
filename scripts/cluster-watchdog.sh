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
#   6. check_certs_and_edge  — TLS SAN/expiry + proxy verification for every hosted host.
#   7. check_shiphook        — Shiphook webhook gateway health (unit, :3141 direct + li-httpd edge) +
#                            config persistence (~/backups/shiphook-*.tar.gz restore) + auto-heal.
#
# --check-only runs every probe but performs NO mutations (safe dry-run).
# Logs go to journalctl (ExecStart) and /var/log/cluster-watchdog.log (best-effort).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Honour REPO_ROOT from the environment (systemd unit sets it to the checkout);
# fall back to the script's own location for local/ad-hoc runs.
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
# When installed to /usr/local/bin, SCRIPT_DIR/.. is /usr/local (no repo). Fall back to known checkouts.
if [[ ! -f "${REPO_ROOT}/scripts/edge-lis-apply.sh" ]]; then
  for _cand in /home/s4il0r/staging/homelab-k3s /home/s4il0r/homelab-k3s; do
    if [[ -f "${_cand}/scripts/edge-lis-apply.sh" ]]; then REPO_ROOT="$_cand"; break; fi
  done
fi
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
CERT_WARN_DAYS="${CERT_WARN_DAYS:-30}"
CERT_CRIT_DAYS="${CERT_CRIT_DAYS:-15}"
EDGE_CERT_HEAL_THRESHOLD="${EDGE_CERT_HEAL_THRESHOLD:-2}"
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

ok_code() { case "$1" in 2[0-9][0-9]|3[0-9][0-9]|401|403) return 0 ;; *) return 1 ;; esac; }  # 401/403 = auth-required => proxy is up

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

# --- 6. check_certs_and_edge (TLS SAN/expiry + proxy verification for every hosted service) ---
# Verifies for each host from li-httpd (homelab.httpd.toml) and nginx (/etc/nginx/gitlab-edge/*.conf):
#   - TLS cert SAN contains the host, expiry days left (warn <30d, crit <15d)
#   - curl ssl_verify_result == 0 (verified) when hosted
#   - proxy works: curl --resolve host:443:127.0.0.1 https://host/ or /health  -> ok_code
#                 plus curl -H "Host: host" http://127.0.0.1:8080/  (li-httpd ingress)
# Fail streak >=2 triggers edge re-apply (+ certbot renewal if needed).
check_certs_and_edge() {
  local toml_candidates=("/run/li-httpd/homelab.httpd.toml" "${REPO_ROOT}/k8s/edge/homelab.httpd.toml")
  local toml="" _c
  for _c in "${toml_candidates[@]}"; do if [[ -f "$_c" ]]; then toml="$_c"; break; fi; done

  local tmp_hosts tmp_li tmp_nginx
  tmp_hosts=$(mktemp)
  tmp_li=$(mktemp)
  tmp_nginx=$(mktemp)
  # --- collect LI hosts ---
  if [[ -n "$toml" && -f "$toml" ]]; then
    grep -E 'host\s*=' "$toml" 2>/dev/null | sed -E 's/.*host\s*=\s*"([^"]+)".*/\1/' | sort -u >"$tmp_li" || true
    cat "$tmp_li" >>"$tmp_hosts" || true
  fi
  # --- collect nginx server_name hosts (live config via nginx -T -c, fallback to snippets) ---
  if command -v nginx >/dev/null 2>&1 && sudo nginx -T -c /etc/nginx/gitlab-edge/nginx.conf 2>&1 | grep -q "server_name"; then
    sudo nginx -T -c /etc/nginx/gitlab-edge/nginx.conf 2>&1 | grep -E '^[[:space:]]*server_name' 2>/dev/null \
      | sed -E 's/.*server_name[[:space:]]+(.*);/\1/' \
      | tr ' ' '\n' | tr ';' '\n' | sed 's/\r//g' \
      | grep -E '\.' | grep -v '^_' | grep -v '192\.168' \
      | grep -v '^\s*$' | sort -u >"$tmp_nginx" || true
    cat "$tmp_nginx" >>"$tmp_hosts" || true
  elif nginx -T -c /etc/nginx/gitlab-edge/nginx.conf 2>&1 | grep -q "server_name"; then
    nginx -T -c /etc/nginx/gitlab-edge/nginx.conf 2>&1 | grep -E '^[[:space:]]*server_name' 2>/dev/null \
      | sed -E 's/.*server_name[[:space:]]+(.*);/\1/' \
      | tr ' ' '\n' | tr ';' '\n' | sed 's/\r//g' \
      | grep -E '\.' | grep -v '^_' | grep -v '192\.168' \
      | grep -v '^\s*$' | sort -u >"$tmp_nginx" || true
    cat "$tmp_nginx" >>"$tmp_hosts" || true
  elif [[ -f /etc/nginx/gitlab-edge/nginx.conf ]]; then
    grep -hE '^[[:space:]]*server_name' /etc/nginx/gitlab-edge/nginx.conf 2>/dev/null \
      | sed -E 's/.*server_name[[:space:]]+(.*);/\1/' \
      | tr ' ' '\n' | tr ';' '\n' | sed 's/\r//g' \
      | grep -E '\.' | grep -v '^_' | grep -v '192\.168' \
      | grep -v '^\s*$' | sort -u >"$tmp_nginx" || true
    cat "$tmp_nginx" >>"$tmp_hosts" || true
  elif ls /etc/nginx/gitlab-edge/*.conf >/dev/null 2>&1; then
    grep -hE '^[[:space:]]*server_name' /etc/nginx/gitlab-edge/*.conf 2>/dev/null \
      | sed -E 's/.*server_name[[:space:]]+(.*);/\1/' \
      | tr ' ' '\n' | tr ';' '\n' | sed 's/\r//g' \
      | grep -E '\.' | grep -v '^_' | grep -v '192\.168' \
      | grep -v '^\s*$' | sort -u >"$tmp_nginx" || true
    cat "$tmp_nginx" >>"$tmp_hosts" || true
  fi

  if [[ ! -s "$tmp_hosts" ]]; then
    log "certs-edge: no hosts discovered (toml=${toml:-none} nginx missing)"
    rm -f "$tmp_hosts" "$tmp_li" "$tmp_nginx"
    return 0
  fi
  sort -u "$tmp_hosts" -o "$tmp_hosts"
  # keep nginx set for edge-type checks
  sort -u "$tmp_nginx" -o "$tmp_nginx" 2>/dev/null || true
  sort -u "$tmp_li" -o "$tmp_li" 2>/dev/null || true

  local total; total=$(wc -l <"$tmp_hosts" | tr -d ' ')
  log "certs-edge: probing ${total} hosts (li+nginx union; li=$(wc -l <"$tmp_li" | tr -d ' ') nginx=$(wc -l <"$tmp_nginx" | tr -d ' '))"

  local host
  while IFS= read -r host; do
    [[ -z "$host" ]] && continue
    if [[ "$host" == "192.168.10.33" || "$host" == "192.168.10.31" || "$host" == "192.168.10.32" || "$host" == "192.168.10.40" ]]; then
      continue
    fi
    local is_lan=0
    if [[ "$host" == *.homelab.lan ]]; then
      is_lan=1
    fi

    local san_ok=1 verify_ok=1 proxy_ok=1 proxy8080_ok=1 expiry_ok=1 days_left="?"
    local san_text="" expiry_text="" verify_result="" code443="" code8080="" cert_text=""

    if [[ "$is_lan" -eq 1 ]]; then
      code8080=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" -H "Host: ${host}" "http://127.0.0.1:8080/health" 2>/dev/null) || code8080="000"
      if ! ok_code "$code8080"; then
        local code_tmp
        code_tmp=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" -H "Host: ${host}" "http://127.0.0.1:8080/" 2>/dev/null) || code_tmp="000"
        if ok_code "$code_tmp"; then code8080="$code_tmp"; fi
      fi
      if ok_code "$code8080"; then proxy8080_ok=1; else proxy8080_ok=0; fi
      code443=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" --resolve "${host}:80:127.0.0.1" "http://${host}/health" 2>/dev/null) || code443="000"
      if ! ok_code "$code443" && ok_code "$code8080"; then
        proxy_ok=1
      else
        if ok_code "$code443"; then proxy_ok=1; else proxy_ok=0; fi
      fi
      if [[ "$proxy8080_ok" -eq 1 || "$proxy_ok" -eq 1 ]]; then
        log "certs-edge: ${host} (LAN) proxy 8080=${code8080} :80=${code443} — OK"
        write_streak "$(streak_file "cert-edge-${host}")" 0
        continue
      else
        log "certs-edge: ${host} (LAN) proxy FAIL 8080=${code8080} :80=${code443}"
      fi
    else
      # Determine edge membership: li-httpd vs nginx
      local in_nginx=0 in_li=0
      grep -Fxq "$host" "$tmp_nginx" 2>/dev/null && in_nginx=1
      grep -Fxq "$host" "$tmp_li" 2>/dev/null && in_li=1

      # Host not on nginx :443 (li-httpd only) → check via li 8080/80, skip TLS
      if [[ "$in_nginx" -eq 0 ]]; then
        code8080=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" -H "Host: ${host}" "http://127.0.0.1:8080/health" 2>/dev/null) || code8080="000"
        if ! ok_code "$code8080"; then
          code8080=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" -H "Host: ${host}" "http://127.0.0.1:8080/" 2>/dev/null) || code8080="000"
        fi
        if ok_code "$code8080"; then proxy8080_ok=1; proxy_ok=1; else proxy8080_ok=0; proxy_ok=0; fi
        # TLS not expected for li-only hosts
        san_ok=1; verify_ok=1; expiry_ok=1; code443="n/a (li-only)"; verify_result="n/a"
        if [[ "$proxy_ok" -eq 1 ]]; then
          log "certs-edge: ${host} OK (li-only) proxy 8080=${code8080}"
          write_streak "$(streak_file "cert-edge-${host}")" 0
          continue
        else
          log "certs-edge: ${host} FAIL (li-only) proxy8080=${code8080} host not on nginx :443 (expected via li 8080)"
        fi
      else
        # Host is on nginx :443 → full TLS verification
        if command -v openssl >/dev/null 2>&1; then
          cert_text=$(timeout 5 openssl s_client -connect 127.0.0.1:443 -servername "$host" </dev/null 2>/dev/null | openssl x509 -noout -dates -ext subjectAltName 2>/dev/null) || cert_text=""
          if [[ -z "$cert_text" ]]; then
            log "certs-edge: ${host} openssl s_client failed (no cert)"
            san_ok=0; expiry_ok=0
          else
            if echo "$cert_text" | grep -q "DNS:${host}"; then
              san_ok=1
              san_text="SAN ok"
            else
              san_ok=0
              san_text=$(echo "$cert_text" | tr '\n' ' ' | head -c 200)
              log "certs-edge: ${host} SAN MISMATCH host not in SAN cert=${san_text:-?}"
            fi
            local notAfter notAfter_epoch now_epoch
            notAfter=$(echo "$cert_text" | grep -i "notAfter=" | cut -d= -f2-)
            if [[ -n "$notAfter" ]]; then
              notAfter_epoch=$(date -d "$notAfter" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$notAfter" +%s 2>/dev/null || echo "")
              now_epoch=$(date +%s)
              if [[ -n "$notAfter_epoch" && -n "$now_epoch" ]]; then
                days_left=$(( (notAfter_epoch - now_epoch) / 86400 ))
                expiry_text="${days_left}d left (${notAfter})"
                local warn_days="${CERT_WARN_DAYS:-30}" crit_days="${CERT_CRIT_DAYS:-15}"
                if (( days_left < crit_days )); then
                  expiry_ok=0
                  log "certs-edge: ${host} cert CRIT expiry ${expiry_text} SAN=${san_ok}"
                elif (( days_left < warn_days )); then
                  expiry_ok=1
                  log "certs-edge: ${host} cert WARN expiry ${expiry_text}"
                else
                  expiry_ok=1
                fi
              else
                log "certs-edge: ${host} cert expiry parse fail notAfter=${notAfter:-?}"
                expiry_ok=1
              fi
            fi
          fi
        else
          log "certs-edge: ${host} openssl not found — skip SAN/expiry"
        fi

        local curl_out
        curl_out=$(curl -s -o /dev/null -w '%{http_code}:%{ssl_verify_result}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" --resolve "${host}:443:127.0.0.1" "https://${host}/" 2>/dev/null) || curl_out="000:1"
        code443=$(echo "$curl_out" | cut -d: -f1)
        verify_result=$(echo "$curl_out" | cut -d: -f2)
        if [[ "$verify_result" == "0" ]]; then verify_ok=1; else verify_ok=0; log "certs-edge: ${host} ssl_verify_result=${verify_result} code=${code443} (expected 0)"; fi
        if ok_code "$code443"; then proxy_ok=1
        else
          local code_h verify_h out_h
          out_h=$(curl -s -o /dev/null -w '%{http_code}:%{ssl_verify_result}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" --resolve "${host}:443:127.0.0.1" "https://${host}/health" 2>/dev/null) || out_h="000:1"
          code_h=$(echo "$out_h" | cut -d: -f1)
          verify_h=$(echo "$out_h" | cut -d: -f2)
          if ok_code "$code_h" && [[ "$verify_h" == "0" ]]; then
            proxy_ok=1; code443="${code_h} (via /health)"; verify_ok=1
          else
            proxy_ok=0
          fi
        fi

        # li-httpd direct proxy is informational for nginx hosts (may be 404 if not on li)
        code8080=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" -H "Host: ${host}" "http://127.0.0.1:8080/health" 2>/dev/null) || code8080="000"
        if ! ok_code "$code8080"; then
          code8080=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" -H "Host: ${host}" "http://127.0.0.1:8080/" 2>/dev/null) || code8080="000"
        fi
        if ok_code "$code8080"; then proxy8080_ok=1; else proxy8080_ok=0; fi

        if [[ "$san_ok" -eq 1 && "$expiry_ok" -eq 1 && "$verify_ok" -eq 1 && "$proxy_ok" -eq 1 ]]; then
          log "certs-edge: ${host} OK cert SAN=${san_ok} verify=${verify_result} proxy=${code443} 8080=${code8080} expiry=${expiry_text:-?}"
          write_streak "$(streak_file "cert-edge-${host}")" 0
          continue
        else
          log "certs-edge: ${host} FAIL san=${san_ok} expiry=${expiry_ok}(${expiry_text:-?}) verify=${verify_result:-?} proxy443=${code443} proxy8080=${code8080}"
        fi
      fi
    fi

    local sf; sf=$(streak_file "cert-edge-${host}")
    local streak; streak=$(read_streak "$sf"); streak=$((streak + 1)); write_streak "$sf" "$streak"
    log "certs-edge: ${host} streak=${streak}/${EDGE_CERT_HEAL_THRESHOLD:-2}"
    if [[ "$streak" -lt "${EDGE_CERT_HEAL_THRESHOLD:-2}" ]]; then continue; fi

    log "certs-edge: ${host} threshold reached — healing edge (re-apply configs, reload, certbot if needed)"
    mut bash "$EDGE_LIS_APPLY" --no-reload 2>/dev/null || true
    mut bash "$EDGE_NGINX_APPLY" --no-reload 2>/dev/null || true
    mut systemctl reload nginx-gitlab-edge.service 2>/dev/null || mut systemctl restart nginx-gitlab-edge.service 2>/dev/null || true
    mut systemctl reload li-httpd-homelab.service 2>/dev/null || mut systemctl restart li-httpd-homelab.service 2>/dev/null || true

    if [[ "$san_ok" -eq 0 || "$verify_ok" -eq 0 || "$expiry_ok" -eq 0 ]]; then
      local cert_dir=""
      if [[ -d /etc/letsencrypt/live ]]; then
        for d in /etc/letsencrypt/live/*; do
          [[ -d "$d" ]] || continue
          if sudo openssl x509 -noout -ext subjectAltName -in "$d/fullchain.pem" 2>/dev/null | grep -q "DNS:${host}"; then
            cert_dir="$d"; break
          fi
          if [[ "$(basename "$d")" == "$host" ]]; then cert_dir="$d"; fi
        done
      fi
      if [[ -n "$cert_dir" ]]; then
        local cert_name; cert_name=$(basename "$cert_dir")
        log "certs-edge: ${host} attempt certbot renew --cert-name ${cert_name}"
        mut sudo certbot renew --cert-name "$cert_name" --no-self-upgrade 2>/dev/null || log "certs-edge: certbot renew for ${cert_name} failed/skipped"
        mut bash "$EDGE_NGINX_APPLY" --no-reload 2>/dev/null || true
        mut systemctl reload nginx-gitlab-edge.service 2>/dev/null || true
      else
        log "certs-edge: ${host} no matching /etc/letsencrypt/live/* dir — try generic helper"
        local helper=""
        case "$host" in
          julianmkleber.com|www.julianmkleber.com) helper="$PORTFOLIO_CERTBOT" ;;
          bureauzilla.com|www.bureauzilla.com|supabase.bureauzilla.com) helper="${REPO_ROOT}/scripts/edge-bureauzilla-certbot.sh" ;;
          collins.d3bu7.com) helper="${REPO_ROOT}/scripts/edge-collins-certbot.sh" ;;
          crm.sail.black) helper="${REPO_ROOT}/scripts/edge-crm-certbot.sh" ;;
          demo.bureauzilla.com) helper="${REPO_ROOT}/scripts/edge-demo-bureauzilla-certbot.sh" ;;
          meet.d3bu7.com) helper="${REPO_ROOT}/scripts/edge-meetfriends-certbot.sh" ;;
          telekom.d3bu7.com) helper="${REPO_ROOT}/scripts/edge-telekom-certbot.sh" ;;
          *.obsevia.com|obsevia.com|www.obsevia.com) helper="${REPO_ROOT}/scripts/edge-obsevia-demos-certbot.sh" ;;
        esac
        if [[ -n "$helper" && -x "$helper" ]]; then
          log "certs-edge: ${host} helper ${helper} — invoke"
          mut bash "$helper" 2>/dev/null || true
        fi
      fi
    fi
    write_streak "$sf" 0
  done <"$tmp_hosts"
  rm -f "$tmp_hosts" "$tmp_li" "$tmp_nginx"
  log "certs-edge: complete"
}

# --- 7. check_shiphook (webhook deploy gateway health + config persistence) ---
# "shiphook" = self-hosted Node webhook (https://github.com/cap-jmk-real/shiphook) on blackpearl :3141.
# Lives at ~/staging/shiphook-server/shiphook.yaml (port 3141, 5 apps on majico.d3bu7.com) +
# secret file ~/staging/shiphook-server/.shiphook.staging.secret. Routed via li-httpd
# upstream shiphook_staging (127.0.0.1:3141) for POST /deploy/staging* and POST /deploy/staging/{qroma,ducah,dp,agentic-book}.
# Config is NOT git-tracked (outside repo; only *.example in repo); persistence = ~/backups/shiphook-*.tar.gz.
# Fix for "shiphook" misspelling: this also covers generic webhook (shiphook) configs — same probe/heal.
SHIPHOOK_HEAL_THRESHOLD="${SHIPHOOK_HEAL_THRESHOLD:-2}"
SHIPHOOK_CONFIG="${SHIPHOOK_CONFIG:-/home/s4il0r/staging/shiphook-server/shiphook.yaml}"
SHIPHOOK_SECRET_FILE="${SHIPHOOK_SECRET_FILE:-/home/s4il0r/staging/shiphook-server/.shiphook.staging.secret}"
SHIPHOOK_BACKUP_GLOB="${SHIPHOOK_BACKUP_GLOB:-/home/s4il0r/backups/shiphook-*.tar.gz}"
SHIPHOOK_SERVICE="shiphook-staging.service"
check_shiphook() {
  local streakf; streakf=$(streak_file shiphook)
  local unit_ok=0 config_ok=1 secret_ok=1 direct_ok=0 edge_ok=0
  local direct_code="" edge_code="" edge_code_tmp=""
  local reason=""

  if systemctl is-active --quiet "$SHIPHOOK_SERVICE" 2>/dev/null; then unit_ok=1; else reason+="unit-down "; fi
  if [[ -s "$SHIPHOOK_CONFIG" ]]; then
    if grep -q "port:" "$SHIPHOOK_CONFIG" 2>/dev/null && grep -q "apps:" "$SHIPHOOK_CONFIG" 2>/dev/null; then
      config_ok=1
    else
      config_ok=0; reason+="config-corrupt "
    fi
  else
    config_ok=0; reason+="config-missing "
  fi
  if [[ -s "$SHIPHOOK_SECRET_FILE" ]]; then secret_ok=1; else secret_ok=0; reason+="secret-missing "; fi

  # Canonical shiphook vhost (docs/obsevia-demo-ci-shiphook.md):
  #   POST /deploy/staging/qroma @ host shiphook.obsevia.d3bu7.com -> 401=up, 5xx/000=down
  direct_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" \
    -X POST -H "Host: shiphook.obsevia.d3bu7.com" "http://127.0.0.1:3141/deploy/staging/qroma" 2>/dev/null) || direct_code="000"
  if [[ "$direct_code" == "401" ]] || ok_code "$direct_code"; then direct_ok=1; else reason+="direct-${direct_code} "; fi

  edge_code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" -H "Host: majico.d3bu7.com" "http://127.0.0.1:8080/deploy/staging" 2>/dev/null) || edge_code="000"
  if ok_code "$edge_code" || [[ "$edge_code" == "401" ]]; then edge_ok=1; else reason+="edge8080-${edge_code} "; fi
  if [[ "$edge_ok" -eq 0 ]]; then
    edge_code_tmp=$(http_code_url "http://majico.d3bu7.com/deploy/staging" "majico.d3bu7.com:80:127.0.0.1")
    if ok_code "$edge_code_tmp" || [[ "$edge_code_tmp" == "401" ]]; then edge_ok=1; edge_code="${edge_code_tmp}(via-resolve)"; else reason+="edge80-${edge_code_tmp} "; fi
  fi

  log "shiphook: unit=${unit_ok} config=${config_ok} secret=${secret_ok} direct=${direct_code} edge=${edge_code} reason=${reason:-ok}"

  if [[ "$unit_ok" -eq 1 && "$config_ok" -eq 1 && "$secret_ok" -eq 1 && "$direct_ok" -eq 1 && "$edge_ok" -eq 1 ]]; then
    write_streak "$streakf" 0
    log "shiphook: OK"
    return 0
  fi

  local streak; streak=$(read_streak "$streakf"); streak=$((streak + 1)); write_streak "$streakf" "$streak"
  log "shiphook: DEGRADED streak=${streak}/${SHIPHOOK_HEAL_THRESHOLD} ${reason}(direct=${direct_code} edge=${edge_code})"
  if [[ "$streak" -lt "$SHIPHOOK_HEAL_THRESHOLD" ]]; then return 0; fi

  log "shiphook: threshold reached — healing (restore config if needed + restart)"
  if [[ "$config_ok" -eq 0 || "$secret_ok" -eq 0 ]]; then
    local latest=""; latest=$(ls -t $SHIPHOOK_BACKUP_GLOB 2>/dev/null | head -1) || true
    if [[ -n "$latest" && -f "$latest" ]]; then
      log "shiphook: restoring config from $latest"
      mut mkdir -p "$(dirname "$SHIPHOOK_CONFIG")" 2>/dev/null || true
      mut tar -xzf "$latest" -C "$(dirname "$(dirname "$SHIPHOOK_CONFIG")")" 2>/dev/null || log "shiphook: tar restore failed"
      mut tar -xzf "$latest" -C /home/s4il0r/staging 2>/dev/null || true
    else
      log "shiphook: no backup $SHIPHOOK_BACKUP_GLOB found — cannot restore; will try service restart only"
    fi
    if [[ -s "$SHIPHOOK_CONFIG" ]]; then log "shiphook: config present after restore"; else log "shiphook: config STILL missing after restore"; fi
  fi

  if ! ls $SHIPHOOK_BACKUP_GLOB >/dev/null 2>&1; then
    log "shiphook: no backup exists — creating one"
    mut mkdir -p "$(dirname "$SHIPHOOK_BACKUP_GLOB")" 2>/dev/null || true
    mut bash -c "tar -czf /home/s4il0r/backups/shiphook-$(date -u +%Y%m%dT%H%M%SZ).tar.gz -C /home/s4il0r/staging shiphook-server/shiphook.yaml shiphook-server/.shiphook.staging.secret 2>/dev/null && echo shiphook backup created" || true
  fi

  if ! systemctl is-active --quiet "$SHIPHOOK_SERVICE" 2>/dev/null; then
    mut systemctl start "$SHIPHOOK_SERVICE" 2>/dev/null || mut systemctl restart "$SHIPHOOK_SERVICE" 2>/dev/null || true
  else
    mut systemctl restart "$SHIPHOOK_SERVICE" 2>/dev/null || true
  fi
  if [[ "$edge_ok" -eq 0 ]]; then
    mut bash "$EDGE_LIS_APPLY" --no-reload 2>/dev/null || true
    mut systemctl reload li-httpd-homelab.service 2>/dev/null || mut systemctl restart li-httpd-homelab.service 2>/dev/null || true
  fi
  sleep 3
  local direct2 edge2
  direct2=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Host: shiphook.obsevia.d3bu7.com" "http://127.0.0.1:3141/deploy/staging/qroma" 2>/dev/null) || direct2="000"
  edge2=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$PROBE_TIMEOUT" --max-time "$PROBE_MAX" -H "Host: majico.d3bu7.com" "http://127.0.0.1:8080/deploy/staging" 2>/dev/null) || edge2="000"
  log "shiphook: after heal direct=${direct2} edge=${edge2} unit=$(systemctl is-active "$SHIPHOOK_SERVICE" 2>/dev/null || echo inactive)"
  write_streak "$streakf" 0
}


# --- agentic-book auth flow (Supabase/Next.js PKCE) probe ---
# Catches the regression "browser client stores PKCE code_verifier in
# localStorage, server route expects it in a cookie" (symptom: /auth/callback
# -> 307 /account?error=PKCE code verifier not found in storage).
# Also catches a misconfigured auth server or broken edge.
#
# Probes:
#   1. GET https://agentic-book.org/                        expect 200
#   2. GET https://agentic-book.org/account                 expect 200 or 307
#   3. GET https://supabase.agentic-book.org/auth/v1/versions  expect 401 (auth-required = up)
#
# On streak>=2 log the exact failure + restart agentic-app deployment if the
# app itself is down (bad-image class, not an edge issue).
AGBook_Auth_HEAL_THRESHOLD="${AGBook_Auth_HEAL_THRESHOLD:-2}"
AGBook_APP_HOST="https://agentic-book.org"
AGBook_AUTH_HOST="https://supabase.agentic-book.org"
check_agentic_book_auth() {
    local streakf
    streakf=$(streak_file agentic-book-auth)
    local reasons=""
    local c_home c_account c_versions
    c_home=$(curl -s -o /dev/null -w '%{http_code}' --resolve agentic-book.org:443:127.0.0.1 --connect-timeout 5 --max-time 10 "${AGBook_APP_HOST}/" 2>/dev/null) || c_home="000"
    c_account=$(curl -s -o /dev/null -w '%{http_code}' --resolve agentic-book.org:443:127.0.0.1 --connect-timeout 5 --max-time 10 "${AGBook_APP_HOST}/account" 2>/dev/null) || c_account="000"
    c_versions=$(curl -s -o /dev/null -w '%{http_code}' --resolve supabase.agentic-book.org:443:127.0.0.1 --connect-timeout 5 --max-time 10 "${AGBook_AUTH_HOST}/auth/v1/versions" 2>/dev/null) || c_versions="000"

    # app home — non-2xx/3xx is suspect (4xx/5xx/000)
    if [[ "$c_home" == "000" ]] || { [ "$c_home" -ge 400 ] 2>/dev/null && [ "$c_home" -lt 500 ] || [ "$c_home" -ge 500 ] 2>/dev/null; }; then
        case "$c_home" in
          000|4*|5*) reasons+="app:/=${c_home} ";;
        esac
    fi
    # /account — only 000 or 5xx is bad (200 ok, 30x redirect ok)
    if [[ "$c_account" == "000" ]] || { [ "$c_account" -ge 500 ] 2>/dev/null; }; then
        case "$c_account" in
          000|5*) reasons+="app:/account=${c_account} ";;
        esac
    fi
    # supabase auth /auth/v1/versions — 401 (auth-required) is "up"
    if [[ "$c_versions" == "000" ]]; then
        reasons+="supabase:/auth/v1/versions=${c_versions}"
    elif { [ "$c_versions" -ge 500 ] 2>/dev/null; } && [ "$c_versions" != "401" ]; then
        reasons+="supabase:/auth/v1/versions=${c_versions} "
    fi

    log "agentic-book-auth: /=${c_home} /account=${c_account} auth/versions=${c_versions}${reasons:+  reasons=[${reasons}]}"
    if [[ -z "$reasons" ]]; then
        write_streak "$streakf" 0
        return 0
    fi

    local streak
    streak=$(read_streak "$streakf")
    streak=$((streak + 1))
    write_streak "$streakf" "$streak"
    log "agentic-book-auth: DEGRADED streak=${streak}/${AGBook_Auth_HEAL_THRESHOLD} reasons=[${reasons}]"
    [[ "$streak" -lt "$AGBook_Auth_HEAL_THRESHOLD" ]] && return 0

    # Only heal if the APP itself is down (not the Supabase endpoint — that's an
    # infra issue the operator must fix, not an image issue).
    case "$c_home" in
      000|5*)
        log "agentic-book-auth: threshold reached - restarting agentic-app (app is down: /=${c_home})"
        mut kubectl -n agentic-book rollout restart deployment/agentic-app 2>/dev/null
        sleep 5
        c_home_after=$(curl -s -o /dev/null -w '%{http_code}' --resolve agentic-book.org:443:127.0.0.1 --max-time 5 "${AGBook_APP_HOST}/" 2>/dev/null) || c_home_after="000"
        log "agentic-book-auth: after-heal /=${c_home_after}"
        ;;
    esac
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
check_certs_and_edge
check_shiphook
check_agentic_book_auth
keep_portfolio_up
keep_librebase_staging_up
check_services
prune_stale
prune_images_gated
rotate_backups
log "=== cluster-watchdog run complete ==="
