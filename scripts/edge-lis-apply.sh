#!/usr/bin/env bash
# Apply native li-httpd as homelab edge ingress on blackpearl (:80 HTTP + :8443 TLS dev).
# Production GitLab HTTPS: nginx :443 — see scripts/edge-nginx-apply.sh.
#
# Serialization: flock(2) on /run/li-httpd/edge-apply.lock inside this script only.
# Do NOT wrap invocations in an outer flock (systemd/cron) — that deadlocks with inner flock.
#
# Only li-httpd-homelab.service runs --render-only on start. TLS waits for .render-ready.
# Manual: bash scripts/edge-lis-apply.sh  (single render + sequential HTTP then TLS restart)
set -euo pipefail

RENDER_ONLY=0
INSTALL_SYSTEMD=0
RELOAD=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --render-only) RENDER_ONLY=1; shift ;;
    --install-systemd) INSTALL_SYSTEMD=1; shift ;;
    --no-reload) RELOAD=0; shift ;;
    -h|--help)
      echo "usage: edge-lis-apply.sh [--render-only] [--install-systemd] [--no-reload]"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EDGE_DIR="${REPO_ROOT}/k8s/edge"

LIC_ROOT="${LIC_ROOT:-}"
if [[ -z "$LIC_ROOT" ]]; then
  for candidate in \
    "${HOME}/staging/lic" \
    "${REPO_ROOT}/../li/lic" \
    "/home/s4il0r/staging/lic"; do
    if [[ -f "${candidate}/scripts/httpd_config.py" ]]; then
      LIC_ROOT="$candidate"
      break
    fi
  done
fi
[[ -n "$LIC_ROOT" ]] || LIC_ROOT="${HOME}/staging/lic}"
LIS_ROOT="${LIS_ROOT:-}"
if [[ -z "$LIS_ROOT" ]]; then
  for candidate in \
    "${HOME}/staging/lis" \
    "/home/s4il0r/staging/lis"; do
    [[ -d "$candidate" ]] && LIS_ROOT="$candidate" && break
  done
fi
[[ -n "$LIS_ROOT" ]] || LIS_ROOT="${HOME}/staging/lis}"
LI_HTTPD_ROOT="${LI_HTTPD_ROOT:-}"
if [[ -z "$LI_HTTPD_ROOT" ]]; then
  for candidate in \
    "${HOME}/staging/li-httpd" \
    "/home/s4il0r/staging/li-httpd"; do
    if [[ -f "${candidate}/scripts/flatten-httpd-config.py" ]]; then
      LI_HTTPD_ROOT="$candidate"
      break
    fi
  done
fi
[[ -n "$LI_HTTPD_ROOT" ]] || LI_HTTPD_ROOT="${HOME}/staging/li-httpd}"
MAJICO_HTTPD_TOML="${MAJICO_HTTPD_TOML:-/home/s4il0r/staging/majico-deploy/deploy/staging/edge/majico-staging.httpd.toml}"

if [[ -f "${LI_HTTPD_ROOT}/scripts/flatten-httpd-config.py" ]]; then
  FLATTEN="${LI_HTTPD_ROOT}/scripts/flatten-httpd-config.py"
  FLATTEN_PYTHONPATH="${LI_HTTPD_ROOT}/scripts"
elif [[ -f "${LIC_ROOT}/scripts/flatten-httpd-config.py" ]]; then
  FLATTEN="${LIC_ROOT}/scripts/flatten-httpd-config.py"
  FLATTEN_PYTHONPATH="${LIC_ROOT}/scripts"
else
  FLATTEN=""
  FLATTEN_PYTHONPATH=""
fi
SETUP_TLS="${LIC_ROOT}/scripts/setup-tls-httpd.py"
GEN_HTTPS="${EDGE_DIR}/gen-https-overlay.py"
RUNTIME_DIR="/run/li-httpd"
EDGE_APPLY_LOCK="${RUNTIME_DIR}/edge-apply.lock"
RENDER_READY="${RUNTIME_DIR}/.render-ready"
MERGED="${RUNTIME_DIR}/homelab.httpd.toml"
MERGED_TLS="${RUNTIME_DIR}/homelab.https.httpd.toml"
RUNTIME="${RUNTIME_DIR}/homelab.runtime.conf"
RUNTIME_TLS="${RUNTIME_DIR}/homelab.tls.runtime.conf"
TLS_CERT_DIR="/var/lib/li-httpd/tls/homelab"

[[ -f "${EDGE_DIR}/homelab.httpd.toml" ]] || { echo "missing ${EDGE_DIR}/homelab.httpd.toml" >&2; exit 1; }
[[ -f "$FLATTEN" ]] || { echo "missing flatten script at $FLATTEN (sync lic to ~/staging/lic)" >&2; exit 1; }
[[ -f /usr/local/bin/li-httpd ]] || { echo "missing /usr/local/bin/li-httpd — run build-edge-li-httpd.sh first" >&2; exit 1; }

mkdir -p "$RUNTIME_DIR" /var/lib/li-httpd/empty "$TLS_CERT_DIR"

render_edge_configs() {
  rm -f "$RENDER_READY"
  local inputs=("${EDGE_DIR}/homelab.httpd.toml")
  if [[ -f "$MAJICO_HTTPD_TOML" ]]; then
    inputs+=("$MAJICO_HTTPD_TOML")
  else
    echo "warn: majico TOML not found at ${MAJICO_HTTPD_TOML}" >&2
  fi

  export LIS_ROOT LIC_ROOT LI_HTTPD_ROOT
  python3 "${EDGE_DIR}/merge-httpd-config.py" "${inputs[@]}" -o "$MERGED" --validate

  export PYTHONPATH="${FLATTEN_PYTHONPATH}${PYTHONPATH:+:$PYTHONPATH}"
  python3 "$FLATTEN" "$MERGED" -o "$RUNTIME"
  python3 "${SCRIPT_DIR}/edge-inject-runtime-limits.py" "$MERGED" "$RUNTIME"
  python3 "${SCRIPT_DIR}/reorder-edge-upstream-peers.py" "$RUNTIME"
  echo "flatten http: $RUNTIME ($(wc -l <"$RUNTIME") lines)"

  python3 "$GEN_HTTPS" "$MERGED" -o "$MERGED_TLS"

  if [[ -f "$SETUP_TLS" ]] && ! grep -q 'mode = "lets_encrypt"' "$MERGED_TLS"; then
    python3 "$SETUP_TLS" "$MERGED_TLS"
  elif grep -q 'mode = "lets_encrypt"' "$MERGED_TLS"; then
    echo "warn: skipping setup-tls for lets_encrypt overlay (use certbot + homelab-edge manual cert)" >&2
  else
    echo "warn: missing $SETUP_TLS — TLS certs must exist under $TLS_CERT_DIR" >&2
  fi

  python3 "$FLATTEN" "$MERGED_TLS" -o "$RUNTIME_TLS"
  python3 "${SCRIPT_DIR}/edge-inject-runtime-limits.py" "$MERGED" "$RUNTIME_TLS"
  python3 "${SCRIPT_DIR}/reorder-edge-upstream-peers.py" "$RUNTIME_TLS"
  echo "flatten tls: $RUNTIME_TLS ($(wc -l <"$RUNTIME_TLS") lines)"

  date -u +%Y-%m-%dT%H:%M:%SZ >"$RENDER_READY"
  echo "edge-lis-apply: render-ready $(cat "$RENDER_READY")"
}

RUNTIME_PRE="${RUNTIME}.pre-apply"
RUNTIME_TLS_PRE="${RUNTIME_TLS}.pre-apply"
if [[ -f "$RUNTIME" ]]; then cp -a "$RUNTIME" "$RUNTIME_PRE"; else : >"$RUNTIME_PRE"; fi
if [[ -f "$RUNTIME_TLS" ]]; then cp -a "$RUNTIME_TLS" "$RUNTIME_TLS_PRE"; else : >"$RUNTIME_TLS_PRE"; fi

(
  flock -w 300 9 || { echo "timeout waiting for $EDGE_APPLY_LOCK (parallel edge-lis-apply?)" >&2; exit 1; }
  render_edge_configs
) 9>"$EDGE_APPLY_LOCK" || exit 1

if [[ "$RENDER_ONLY" -eq 1 ]]; then
  exit 0
fi

if [[ "$INSTALL_SYSTEMD" -eq 1 ]]; then
  install -d /usr/local/bin
  install -m 755 "${SCRIPT_DIR}/edge-health-probe.sh" /usr/local/bin/edge-health-probe.sh
  install -m 755 "${LIC_ROOT}/scripts/flatten-httpd-config.sh" /usr/local/bin/flatten-httpd-config.sh 2>/dev/null || true
  for unit in li-httpd-homelab.service li-httpd-homelab-tls.service \
    nginx-gitlab-edge.service \
    li-httpd-edge-watchdog.service li-httpd-edge-watchdog.timer; do
    sed -e "s|/home/s4il0r/staging/homelab-k3s|${REPO_ROOT}|g" \
        -e "s|/home/s4il0r/staging/beelink-cleanup|${REPO_ROOT}|g" \
      "${EDGE_DIR}/${unit}" >/etc/systemd/system/${unit}
  done
  systemctl daemon-reload
  systemctl disable --now li-httpd-majico-staging.service 2>/dev/null || true
  systemctl disable --now caddy.service 2>/dev/null || true
  systemctl enable li-httpd-homelab.service li-httpd-homelab-tls.service
  systemctl enable nginx-gitlab-edge.service 2>/dev/null || true
  systemctl enable li-httpd-edge-watchdog.timer
fi

if [[ "$RELOAD" -eq 1 ]] && [[ -f "$RUNTIME_PRE" ]] && [[ -f "$RUNTIME_TLS_PRE" ]] \
  && cmp -s "$RUNTIME_PRE" "$RUNTIME" && cmp -s "$RUNTIME_TLS_PRE" "$RUNTIME_TLS"; then
  echo "edge-lis-apply: runtime conf unchanged - skip li-httpd restart"
  RELOAD=0
fi

if [[ "$RELOAD" -eq 1 ]]; then
  if systemctl is-active --quiet li-httpd-homelab.service 2>/dev/null; then
    systemctl restart li-httpd-homelab.service
  elif [[ -f /etc/systemd/system/li-httpd-homelab.service ]]; then
    systemctl enable --now li-httpd-homelab.service
  else
    echo "run: sudo bash scripts/edge-lis-apply.sh --install-systemd" >&2
    exit 1
  fi
  sleep 2
  if systemctl is-active --quiet li-httpd-homelab-tls.service 2>/dev/null; then
    systemctl restart li-httpd-homelab-tls.service
  elif [[ -f /etc/systemd/system/li-httpd-homelab-tls.service ]]; then
    systemctl enable --now li-httpd-homelab-tls.service
  fi
fi

echo "edge-lis-apply: done (li-httpd :80 + :8443 dev TLS; GitLab prod nginx :443)"
