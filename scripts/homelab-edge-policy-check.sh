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
    homelab.httpd.toml|Caddyfile|*.service|*.snippet|README.md) ;;
    *.py) ;;
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
