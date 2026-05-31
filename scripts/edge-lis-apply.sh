#!/usr/bin/env bash
# Apply native li-httpd as homelab edge ingress on blackpearl.
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

LIS_ROOT="${LIS_ROOT:-${HOME}/staging/lis}"
LIC_ROOT="${LIC_ROOT:-${HOME}/staging/lic}"
MAJICO_HTTPD_TOML="${MAJICO_HTTPD_TOML:-/home/s4il0r/staging/majico.xyz/deploy/staging/edge/majico-staging.httpd.toml}"
FLATTEN="${LIC_ROOT}/scripts/flatten-httpd-config.py"
RUNTIME_DIR="/run/li-httpd"
MERGED="${RUNTIME_DIR}/homelab.httpd.toml"
RUNTIME="${RUNTIME_DIR}/homelab.runtime.conf"

[[ -f "${EDGE_DIR}/homelab.httpd.toml" ]] || { echo "missing ${EDGE_DIR}/homelab.httpd.toml" >&2; exit 1; }
[[ -f "$FLATTEN" ]] || { echo "missing flatten script at $FLATTEN (sync lic to ~/staging/lic)" >&2; exit 1; }
[[ -f /usr/local/bin/li-httpd ]] || { echo "missing /usr/local/bin/li-httpd — run lic build-li-httpd.sh first" >&2; exit 1; }

mkdir -p "$RUNTIME_DIR" /var/lib/li-httpd/empty

inputs=("${EDGE_DIR}/homelab.httpd.toml")
if [[ -f "$MAJICO_HTTPD_TOML" ]]; then
  inputs+=("$MAJICO_HTTPD_TOML")
else
  echo "warn: majico TOML not found at ${MAJICO_HTTPD_TOML}" >&2
fi

export LIS_ROOT LIC_ROOT
python3 "${EDGE_DIR}/merge-httpd-config.py" "${inputs[@]}" -o "$MERGED" --validate

export PYTHONPATH="${LIC_ROOT}/scripts${PYTHONPATH:+:$PYTHONPATH}"
python3 "$FLATTEN" "$MERGED" -o "$RUNTIME"
echo "flatten: $RUNTIME ($(wc -l <"$RUNTIME") lines)"

if [[ "$RENDER_ONLY" -eq 1 ]]; then
  exit 0
fi

if [[ "$INSTALL_SYSTEMD" -eq 1 ]]; then
  install -d /usr/local/bin
  install -m 755 "${LIC_ROOT}/scripts/flatten-httpd-config.sh" /usr/local/bin/flatten-httpd-config.sh 2>/dev/null || true
  sed "s|/home/s4il0r/staging/beelink-cleanup|${REPO_ROOT}|g" \
    "${EDGE_DIR}/li-httpd-homelab.service" >/etc/systemd/system/li-httpd-homelab.service
  systemctl daemon-reload
  systemctl disable --now li-httpd-majico-staging.service 2>/dev/null || true
  systemctl enable li-httpd-homelab.service
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
fi

echo "edge-lis-apply: done (li-httpd)"
