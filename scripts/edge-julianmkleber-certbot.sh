#!/usr/bin/env bash
# Issue LE cert for julianmkleber.com (+ www) and enable nginx :443 edge.
# Requires public DNS A @/www → Fritz WAN first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EMAIL="${HOMELAB_ACME_EMAIL:-admin@majico.xyz}"
DOMAIN="julianmkleber.com"

if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
  echo "edge-julianmkleber-certbot: requesting LE cert for ${DOMAIN} + www (webroot)"
  sudo mkdir -p /var/lib/li-httpd/.well-known/acme-challenge
  sudo certbot certonly --webroot -w /var/lib/li-httpd --non-interactive --agree-tos \
    -m "${EMAIL}" -d "${DOMAIN}" -d "www.${DOMAIN}" \
  || {
    echo "webroot failed — trying standalone (brief :80 pause)" >&2
    sudo systemctl stop nginx-gitlab-edge.service li-httpd-homelab.service 2>/dev/null || true
    sleep 1
    sudo certbot certonly --standalone --non-interactive --agree-tos \
      -m "${EMAIL}" -d "${DOMAIN}" -d "www.${DOMAIN}"
    sudo systemctl start li-httpd-homelab.service 2>/dev/null || true
    sudo systemctl start nginx-gitlab-edge.service 2>/dev/null || true
  }
fi

sudo bash "${SCRIPT_DIR}/edge-nginx-apply.sh"
echo "edge-julianmkleber-certbot: done — https://${DOMAIN}/ and https://www.${DOMAIN}/"
