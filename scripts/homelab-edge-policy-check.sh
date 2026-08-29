#!/usr/bin/env bash
# Enforce Linux + Li-native edge policy. Exit non-zero on violations.
# See docs/platform-requirements.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
K8S_DIR="${REPO_ROOT}/k8s"
EDGE_DIR="${REPO_ROOT}/k8s/edge"
EDGE_TOML="${EDGE_DIR}/homelab.httpd.toml"
DEPRECATED_EDGE="${EDGE_DIR}/deprecated"

fail=0
warn=0
FIX=0
if [[ "${1:-}" == "--fix" ]]; then
  FIX=1
fi

die() {
  echo "POLICY FAIL: $*" >&2
  fail=1
}

note() {
  echo "POLICY WARN: $*" >&2
  warn=1
}

ok() {
  echo "POLICY OK: $*"
}

fix_log() {
  echo "POLICY FIX: $*" >&2
}

[[ -f "$EDGE_TOML" ]] || die "missing required edge config k8s/edge/homelab.httpd.toml"
ok "homelab.httpd.toml present"

required_hosts=(
  search.klaut.pro
  gitlab.klaut.pro
  deps.klaut.pro
  cwe.klaut.pro
  vault.klaut.pro
)
for host in "${required_hosts[@]}"; do
  grep -q "host = \"${host}\"" "$EDGE_TOML" || die "homelab.httpd.toml missing [[site]] host = \"${host}\""
done
ok "WAN klaut hostnames defined in homelab.httpd.toml"

# --- portfolio / generic WAN healer (incident 2026-08-26: www.julianmkleber.com → lip cert) ---
portfolio_hosts=(julianmkleber.com www.julianmkleber.com)
for host in "${portfolio_hosts[@]}"; do
  if ! grep -q "host = \"${host}\"" "$EDGE_TOML"; then
    if [[ $FIX -eq 1 ]]; then
      fix_log "adding missing [[site]] ${host} -> portfolio"
      cat >>"$EDGE_TOML" <<EOF

[[site]]
host = "${host}"
listen = ":80"

[site.routes]
"GET /health" = "static:healthcheck"
"GET /*" = "proxy:portfolio"
"POST /*" = "proxy:portfolio"
"HEAD /*" = "proxy:portfolio"
EOF
    else
      die "homelab.httpd.toml missing [[site]] host = \"${host}\" (portfolio; SNI fallback to lip — run with --fix)"
    fi
  fi
done
if grep -q "host = \"julianmkleber.com\"" "$EDGE_TOML" && grep -q "host = \"www.julianmkleber.com\"" "$EDGE_TOML"; then
  ok "portfolio WAN hosts defined in homelab.httpd.toml"
fi

# upstream portfolio must include loopback (kube-proxy) — deck IP 192.168.10.26 is fallback only
if grep -q "^\[upstreams\.portfolio\]" "$EDGE_TOML"; then
  peers_line=$(grep -A2 "^\[upstreams\.portfolio\]" "$EDGE_TOML" | grep -E 'peers =' || true)
  if [[ "$peers_line" != *"127.0.0.1:30585"* ]]; then
    if [[ $FIX -eq 1 ]]; then
      fix_log "patching [upstreams.portfolio] peers to include 127.0.0.1:30585 + 192.168.10.26:30585"
      python3 - <<'PY'
import re, pathlib
p=pathlib.Path("k8s/edge/homelab.httpd.toml")
t=p.read_text()
# replace peers array for portfolio with resilient dual-peer
new='peers = ["http://127.0.0.1:30585", "http://192.168.10.26:30585"]'
t=re.sub(r'(\[upstreams\.portfolio\][^\[]*?peers = )\[[^\]]*\]', r'\1[' + new[8:] , t, flags=re.S)
# fallback if regex missed (single line)
if '127.0.0.1:30585' not in t:
    t=t.replace('peers = ["http://192.168.10.26:30585"]', new)
    t=t.replace('peers = ["http://127.0.0.1:30585"]', new)
pathlib.Path("k8s/edge/homelab.httpd.toml").write_text(t)
PY
    else
      die "[upstreams.portfolio] peers missing loopback 127.0.0.1:30585 (got: ${peers_line}) — health probe/healer fallback broken; run with --fix"
    fi
  else
    ok "upstreams.portfolio includes loopback"
  fi
  # also detect misroute: portfolio site must not proxy to lip
  for h in "${portfolio_hosts[@]}"; do
    block=$(grep -A15 "host = \"${h}\"" "$EDGE_TOML" || true)
    if echo "$block" | grep -q "proxy:lip"; then
      if [[ $FIX -eq 1 ]]; then
        fix_log "fixing misroute ${h} proxy:lip -> proxy:portfolio"
        python3 - <<PY
import pathlib, re
p=pathlib.Path("k8s/edge/homelab.httpd.toml")
t=p.read_text()
t=re.sub(r'(host = "www\.julianmkleber\.com".*?proxy:)lip[^\n"]*', r'\1portfolio', t, flags=re.S)
t=re.sub(r'(host = "julianmkleber\.com".*?proxy:)lip[^\n"]*', r'\1portfolio', t, flags=re.S)
pathlib.Path("k8s/edge/homelab.httpd.toml").write_text(t)
PY
      else
        die "site ${h} routes to lip_registry instead of portfolio — misroute (run with --fix)"
      fi
    fi
  done
fi

# gen-https-overlay.py WAN suffix + ACME coverage
GEN="${EDGE_DIR}/gen-https-overlay.py"
if [[ -f "$GEN" ]]; then
  if ! grep -q "julianmkleber" "$GEN"; then
    if [[ $FIX -eq 1 ]]; then
      fix_log "patching ${GEN} WAN_TLS_SUFFIXES + ACME_DOMAINS for julianmkleber.com"
      python3 - <<'PY'
import pathlib, re
p=pathlib.Path("k8s/edge/gen-https-overlay.py")
t=p.read_text()
if ".julianmkleber.com" not in t:
    t=t.replace('WAN_TLS_SUFFIXES = (".klaut.pro"', 'WAN_TLS_SUFFIXES = (".klaut.pro", ".d3bu7.com", ".lilangverse.xyz", ".obsevia.com", ".librebase.xyz", ".julianmkleber.com"')
    if ".julianmkleber.com" not in t:
        t=re.sub(r'WAN_TLS_SUFFIXES = \(([^\)]+)\)', r'WAN_TLS_SUFFIXES = (\1, ".julianmkleber.com")', t)
if 'host == suffix.lstrip' not in t:
    t=t.replace('if any(host.endswith(suffix) for suffix in WAN_TLS_SUFFIXES):',
                'if any(host == suffix.lstrip(".") or host.endswith(suffix) for suffix in WAN_TLS_SUFFIXES):')
if 'julianmkleber.com' not in t.split('ACME_DOMAINS')[1].split(']')[0]:
    t=t.replace('todo.librebase.xyz"', 'todo.librebase.xyz,julianmkleber.com,www.julianmkleber.com"')
    # avoid double append
    t=t.replace('julianmkleber.com,www.julianmkleber.com,www.julianmkleber.com', 'julianmkleber.com,www.julianmkleber.com')
pathlib.Path("k8s/edge/gen-https-overlay.py").write_text(t)
PY
    else
      die "gen-https-overlay.py missing .julianmkleber.com in WAN_TLS_SUFFIXES/ACME_DOMAINS — TLS SNI fallback to lip (run with --fix)"
    fi
  else
    ok "gen-https-overlay.py covers julianmkleber.com"
  fi
  # nginx vhost skeleton
  if [[ ! -f "${EDGE_DIR}/nginx-julianmkleber.conf" ]]; then
    if [[ $FIX -eq 1 ]]; then
      fix_log "creating nginx-julianmkleber.conf skeleton"
      cat >"${EDGE_DIR}/nginx-julianmkleber.conf" <<'EOF'
# julianmkleber.com HTTPS — portfolio (NodePort 30585)
# Backend: k3s NodePort 30585 (portfolio). Cert: /etc/letsencrypt/live/julianmkleber.com/
# Included from nginx-gitlab-edge.conf when LE cert exists.

upstream julianmkleber_portfolio {
    server 127.0.0.1:30585;
    keepalive 8;
}

server {
    listen 443 ssl;
    http2 on;
    server_name julianmkleber.com www.julianmkleber.com;

    ssl_certificate     /etc/letsencrypt/live/julianmkleber.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/julianmkleber.com/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    location = /health {
        default_type text/plain;
        return 200 "ok\n";
    }

    location / {
        proxy_pass http://julianmkleber_portfolio;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Connection "";
        proxy_set_header Accept-Encoding "";
        proxy_buffering off;
    }
}
EOF
    else
      die "missing nginx vhost k8s/edge/nginx-julianmkleber.conf — nginx :443 fallback to lip (run with --fix)"
    fi
  else
    ok "nginx vhost for julianmkleber.com present"
  fi
fi

while IFS= read -r -d '' f; do
  rel="${f#${REPO_ROOT}/}"

  if grep -qE '^[[:space:]]*kind:[[:space:]]*Ingress[[:space:]]*$' "$f"; then
    die "Kubernetes Ingress not allowed (${rel}) — use NodePort + k8s/edge/"
  fi

  if grep -qE '^[[:space:]]*type:[[:space:]]*LoadBalancer[[:space:]]*$' "$f"; then
    die "LoadBalancer Service not allowed (${rel}) — use NodePort + blackpearl edge"
  fi

  if grep -qiE 'ingressClassName:|traefik\.ingress|kubernetes\.io/ingress\.class' "$f"; then
    die "in-cluster ingress controller reference in ${rel}"
  fi

  if grep -qi 'traefik' "$f"; then
    die "traefik reference in ${rel} — k3s must use --disable traefik; edge is li-httpd only"
  fi

  if grep -qiE 'haproxy|envoyproxy|contour' "$f" && grep -qiE 'ingress|gateway' "$f"; then
    die "alternate ingress controller reference in ${rel}"
  fi

  if grep -qE 'C:\\\\|%USERPROFILE%|\\\\Users\\\\' "$f"; then
    die "Windows path in k8s manifest ${rel} — cluster configs are Linux-native"
  fi
done < <(find "$K8S_DIR" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.toml' \) ! -path '*/edge/*' -print0)

while IFS= read -r -d '' f; do
  if grep -qE '^[[:space:]]*ingress:[[:space:]]*$' "$f" && grep -A3 '^[[:space:]]*ingress:[[:space:]]*$' "$f" | grep -qE 'enabled:[[:space:]]*true'; then
    die "ingress.enabled must be false in ${f#${REPO_ROOT}/}"
  fi
done < <(find "$K8S_DIR" -type f \( -name 'helm-values.yaml' -o -name '*-values.yaml' \) -print0 2>/dev/null)

while IFS= read -r -d '' f; do
  case "$f" in
    "${DEPRECATED_EDGE}"/*) continue ;;
  esac
  if grep -qE 'reverse_proxy\b' "$f" 2>/dev/null; then
    die "Caddy reverse_proxy in non-deprecated file ${f#${REPO_ROOT}/} — use homelab.httpd.toml"
  fi
done < <(find "$EDGE_DIR" -type f \( -name 'Caddyfile*' -o -name '*.caddy' -o -name '*.snippet' \) -print0 2>/dev/null)

while IFS= read -r -d '' f; do
  rel="${f#${REPO_ROOT}/}"
  case "$(basename "$f")" in
    homelab.httpd.toml|*.httpd.toml|Caddyfile|*.service|*.snippet|README.md) ;;
    *.py) ;;
    nginx-*.conf) ;;
    *)
      if grep -qiE 'nginx|haproxy|envoy|traefik|kind:[[:space:]]*Ingress' "$f" 2>/dev/null; then
        die "non-approved proxy/ingress in ${rel}"
      fi
      ;;
  esac
done < <(find "$EDGE_DIR" -type f -print0)

for forbidden in nginx.conf haproxy.cfg traefik.yaml traefik.yml; do
  [[ -f "${EDGE_DIR}/${forbidden}" ]] && die "forbidden edge file k8s/edge/${forbidden}"
done

for script in "${SCRIPT_DIR}"/*.sh; do
  [[ -f "$script" ]] || continue
  base="$(basename "$script")"
  [[ "$base" == "edge-caddy-apply.sh" ]] && continue
  if grep -qE '(^|[^#]*)(bash|sudo bash)[[:space:]]+.*edge-caddy-apply\.sh' "$script" 2>/dev/null; then
    die "${base} invokes deprecated edge-caddy-apply.sh — use edge-lis-apply.sh"
  fi
done

grep -qF -- '--disable traefik' "${REPO_ROOT}/docs/k3s-server.md" || die "docs/k3s-server.md must document --disable traefik"
ok "k3s-server.md documents --disable traefik"

[[ -f "${SCRIPT_DIR}/edge-lis-apply.sh" ]] || die "missing edge-lis-apply.sh"
grep -qE '/etc/|/usr/local/' "${SCRIPT_DIR}/edge-lis-apply.sh" || note "edge-lis-apply.sh does not reference expected Linux install paths"


for unit in li-httpd-homelab.service li-httpd-homelab-tls.service; do
  uf="${EDGE_DIR}/${unit}"
  [[ -f "$uf" ]] || die "missing k8s/edge/${unit}"
  grep -qF "edge-lis-apply.sh" "$uf" || die "${unit} ExecStartPre must call edge-lis-apply.sh"
  if grep -qE "ExecStartPre=.*/flock[[:space:]]" "$uf" || grep -qE "ExecStartPre=.*[[:space:]]flock[[:space:]]" "$uf"; then
    die "${unit} must not wrap edge-lis-apply.sh in flock (deadlocks with internal edge-apply.lock)"
  fi
done
ok "li-httpd-homelab systemd units invoke edge-lis-apply directly (no outer flock)"

if [[ "$fail" -ne 0 ]]; then
  echo "homelab-edge-policy-check: FAILED — see docs/platform-requirements.md" >&2
  exit 1
fi

if [[ "$warn" -ne 0 ]]; then
  echo "homelab-edge-policy-check: passed with warnings"
else
  echo "homelab-edge-policy-check: passed"
fi
