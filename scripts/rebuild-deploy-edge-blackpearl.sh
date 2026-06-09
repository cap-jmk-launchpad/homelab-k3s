#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIC_ROOT="${LIC_ROOT:-${HOME}/staging/lic}"
LI_HTTPD_ROOT="${LI_HTTPD_ROOT:-${HOME}/staging/li-httpd}"

bash "${REPO}/scripts/apply-edge-tls-patch.sh"
bash "${REPO}/scripts/apply-edge-proxy-patch.sh"
LIC_ROOT="$LIC_ROOT" LI_HTTPD_ROOT="$LI_HTTPD_ROOT" bash "${REPO}/scripts/build-edge-li-httpd.sh"
sudo systemctl restart li-httpd-homelab.service
sleep 2
sudo systemctl restart li-httpd-homelab-tls.service
sleep 2
systemctl is-active li-httpd-homelab.service li-httpd-homelab-tls.service
echo "rebuild-deploy-edge-blackpearl: done"
