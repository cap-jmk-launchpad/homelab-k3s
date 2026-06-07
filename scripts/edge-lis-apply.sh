#!/usr/bin/env bash
# Apply native li-httpd as homelab edge ingress on blackpearl (:80 HTTP + :443 TLS).
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
LIS_ROOT="${LIS_ROOT:-${HOME}/staging/lis}"
LI_HTTPD_ROOT="${LI_HTTPD_ROOT:-${HOME}/staging/li-httpd}"
MAJICO_HTTPD_TOML="${MAJICO_HTTPD_TOML:-/home/s4il0r/staging/majico-deploy/deploy/staging/edge/majico-staging.httpd.toml}"
# Prefer li-httpd copy when present; lic flatten supports multi-site [[site]] profiles.
if [[ -f "${LI_HTTPD_ROOT}/scripts/flatten-httpd-config.py" ]]; then
  FLATTEN="${LI_HTTPD_ROOT}/scripts/flatten-httpd-config.py"
elif [[ -f "${LIC_ROOT}/scripts/flatten-httpd-config.py" ]]; then
  FLATTEN="${LIC_ROOT}/scripts/flatten-httpd-config.py"
else
  FLATTEN=""
fi
SETUP_TLS="${LIC_ROOT}/scripts/setup-tls-httpd.py"
GEN_HTTPS="${EDGE_DIR}/gen-https-overlay.py"
RUNTIME_DIR="/run/li-httpd"
MERGED="${RUNTIME_DIR}/homelab.httpd.toml"
MERGED_TLS="${RUNTIME_DIR}/homelab.https.httpd.toml"
RUNTIME="${RUNTIME_DIR}/homelab.runtime.conf"
RUNTIME_TLS="${RUNTIME_DIR}/homelab.tls.runtime.conf"
TLS_CERT_DIR="/var/lib/li-httpd/tls/homelab"

[[ -f "${EDGE_DIR}/homelab.httpd.toml" ]] || { echo "missing ${EDGE_DIR}/homelab.httpd.toml" >&2; exit 1; }
[[ -f "$FLATTEN" ]] || { echo "missing flatten script at $FLATTEN (sync lic to ~/staging/lic)" >&2; exit 1; }
[[ -f /usr/local/bin/li-httpd ]] || { echo "missing /usr/local/bin/li-httpd — run lic build-li-httpd.sh first" >&2; exit 1; }

mkdir -p "$RUNTIME_DIR" /var/lib/li-httpd/empty "$TLS_CERT_DIR"

inputs=("${EDGE_DIR}/homelab.httpd.toml")
if [[ -f "$MAJICO_HTTPD_TOML" ]]; then
  inputs+=("$MAJICO_HTTPD_TOML")
else
  echo "warn: majico TOML not found at ${MAJICO_HTTPD_TOML}" >&2
fi

export LIS_ROOT LIC_ROOT LI_HTTPD_ROOT
python3 "${EDGE_DIR}/merge-httpd-config.py" "${inputs[@]}" -o "$MERGED" --validate

export PYTHONPATH="${LI_HTTPD_ROOT}/scripts:${LIC_ROOT}/scripts${PYTHONPATH:+:$PYTHONPATH}"
python3 "$FLATTEN" "$MERGED" -o "$RUNTIME"
echo "flatten http: $RUNTIME ($(wc -l <"$RUNTIME") lines)"

python3 "$GEN_HTTPS" "$MERGED" -o "$MERGED_TLS"

if [[ -f "$SETUP_TLS" ]]; then
  python3 "$SETUP_TLS" "$MERGED_TLS"
else
  echo "warn: missing $SETUP_TLS — TLS certs must exist under $TLS_CERT_DIR" >&2
fi

python3 "$FLATTEN" "$MERGED_TLS" -o "$RUNTIME_TLS"
echo "flatten tls: $RUNTIME_TLS ($(wc -l <"$RUNTIME_TLS") lines)"

if [[ "$RENDER_ONLY" -eq 1 ]]; then
  exit 0
fi

if [[ "$INSTALL_SYSTEMD" -eq 1 ]]; then
  install -d /usr/local/bin
  install -m 755 "${LIC_ROOT}/scripts/flatten-httpd-config.sh" /usr/local/bin/flatten-httpd-config.sh 2>/dev/null || true
  for unit in li-httpd-homelab.service li-httpd-homelab-tls.service; do
    sed -e "s|/home/s4il0r/staging/homelab-k3s|${REPO_ROOT}|g" \
        -e "s|/home/s4il0r/staging/beelink-cleanup|${REPO_ROOT}|g" \
      "${EDGE_DIR}/${unit}" >/etc/systemd/system/${unit}
  done
  systemctl daemon-reload
  systemctl disable --now li-httpd-majico-staging.service 2>/dev/null || true
  systemctl disable --now caddy.service 2>/dev/null || true
  systemctl enable li-httpd-homelab.service li-httpd-homelab-tls.service
fi

if [[ "$RELOAD" -eq 1 ]]; then
  for unit in li-httpd-homelab.service li-httpd-homelab-tls.service; do
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      systemctl restart "$unit"
    elif [[ -f "/etc/systemd/system/$unit" ]]; then
      systemctl enable --now "$unit"
    else
      echo "run: sudo bash scripts/edge-lis-apply.sh --install-systemd" >&2
      exit 1
    fi
  done
fi

echo "edge-lis-apply: done (li-httpd :80 + :443)"
