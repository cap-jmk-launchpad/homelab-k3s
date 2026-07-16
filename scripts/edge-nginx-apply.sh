#!/usr/bin/env bash
# Install nginx as GitLab production edge (:443). li-httpd TLS moves to :8443 for dev.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EDGE_DIR="${REPO_ROOT}/k8s/edge"
NGINX_CONF_DST="/etc/nginx/gitlab-edge/nginx.conf"
NGINX_UNIT="nginx-gitlab-edge.service"

INSTALL_SYSTEMD=0
SKIP_RELOAD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-systemd) INSTALL_SYSTEMD=1; shift ;;
    --no-reload) SKIP_RELOAD=1; shift ;;
    -h|--help)
      echo "usage: edge-nginx-apply.sh [--install-systemd] [--no-reload]"
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if ! command -v nginx >/dev/null 2>&1; then
  echo "edge-nginx-apply: installing nginx package"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
fi

mkdir -p /etc/nginx/gitlab-edge
install -m 644 "${EDGE_DIR}/nginx-gitlab-edge.conf" "$NGINX_CONF_DST"
# search.klaut.pro + research.klaut.pro TLS vhosts (NodePorts 30479 / 30487)
if [[ -f "${EDGE_DIR}/nginx-klaut-pro.conf" ]]; then
  install -m 644 "${EDGE_DIR}/nginx-klaut-pro.conf" /etc/nginx/gitlab-edge/nginx-klaut-pro.conf
  if ! grep -q 'nginx-klaut-pro.conf' "$NGINX_CONF_DST"; then
    # Insert include before final closing brace of http{}
    python3 - <<'PY' "$NGINX_CONF_DST"
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
inc = "    include /etc/nginx/gitlab-edge/nginx-klaut-pro.conf;\n"
if "nginx-klaut-pro.conf" not in text:
    idx = text.rstrip().rfind("}")
    if idx < 0:
        raise SystemExit("edge-nginx-apply: no closing brace in nginx.conf")
    p.write_text(text[:idx] + inc + text[idx:])
PY
  fi
fi
nginx -t -c "$NGINX_CONF_DST"

if [[ "$INSTALL_SYSTEMD" -eq 1 ]]; then
  install -d /usr/local/bin
  install -m 755 "${SCRIPT_DIR}/edge-health-probe.sh" /usr/local/bin/edge-health-probe.sh
  sed -e "s|/home/s4il0r/staging/homelab-k3s|${REPO_ROOT}|g" \
    "${EDGE_DIR}/${NGINX_UNIT}" >/etc/systemd/system/${NGINX_UNIT}
  systemctl daemon-reload
  systemctl enable "${NGINX_UNIT}"
  # Stock nginx.service must not bind :443 (we use standalone config).
  systemctl disable --now nginx.service 2>/dev/null || true
fi

if [[ "$SKIP_RELOAD" -eq 1 ]]; then
  echo "edge-nginx-apply: config installed (--no-reload)"
  exit 0
fi

# Regenerate li-httpd TLS overlay on :8443 before restart.
export HOMELAB_LI_HTTPD_TLS_PORT=":8443"
bash "${SCRIPT_DIR}/edge-lis-apply.sh" --no-reload

systemctl stop li-httpd-homelab-tls.service 2>/dev/null || true
sleep 1

if systemctl is-enabled nginx-gitlab-edge.service &>/dev/null; then
  systemctl restart nginx-gitlab-edge.service
else
  systemctl enable --now nginx-gitlab-edge.service
fi

systemctl restart li-httpd-homelab-tls.service

echo "edge-nginx-apply: done (nginx :443 GitLab prod, li-httpd-tls :8443 dev)"
ss -tlnp | grep -E ':443|:8443|:80 ' | head -20 || true
