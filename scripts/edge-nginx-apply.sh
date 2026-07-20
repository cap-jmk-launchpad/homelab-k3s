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
install -m 644 "${EDGE_DIR}/nginx-collins.conf" /etc/nginx/gitlab-edge/nginx-collins.conf 2>/dev/null || true
OBSEVIA_SNIPPET="${EDGE_DIR}/nginx-obsevia-demos.conf"
obsevia_certs_ready=0
if [[ -f "$OBSEVIA_SNIPPET" ]]; then
  for d in ducah.obsevia.com qroma.obsevia.com unitedhealth.obsevia.com chat.obsevia.com dp.obsevia.com supabase.obsevia.com api.obsevia.com; do
    if [[ -e "/etc/letsencrypt/live/${d}/fullchain.pem" ]] || [[ -L "/etc/letsencrypt/live/${d}/fullchain.pem" ]]; then
      obsevia_certs_ready=1
      break
    fi
  done
fi
if [[ "$obsevia_certs_ready" -eq 1 ]]; then
  sed "/__OBSEVIA_DEMOS_INCLUDE__/r ${OBSEVIA_SNIPPET}" "$NGINX_CONF_DST" \
    | sed '/__OBSEVIA_DEMOS_INCLUDE__/d' >"${NGINX_CONF_DST}.merged"
  mv "${NGINX_CONF_DST}.merged" "$NGINX_CONF_DST"
  echo "edge-nginx-apply: included obsevia demo HTTPS vhosts"
else
  sed '/__OBSEVIA_DEMOS_INCLUDE__/d' "$NGINX_CONF_DST" >"${NGINX_CONF_DST}.merged"
  mv "${NGINX_CONF_DST}.merged" "$NGINX_CONF_DST"
  echo "edge-nginx-apply: obsevia demo HTTPS vhosts skipped (no LE certs under /etc/letsencrypt/live/*.obsevia.com)"
fi
COLLINS_SNIPPET="${EDGE_DIR}/nginx-collins.conf"
collins_cert_ready=0
if [[ -f "$COLLINS_SNIPPET" ]] && { [[ -e "/etc/letsencrypt/live/collins.d3bu7.com/fullchain.pem" ]] || [[ -L "/etc/letsencrypt/live/collins.d3bu7.com/fullchain.pem" ]]; }; then
  collins_cert_ready=1
fi
if [[ "$collins_cert_ready" -eq 1 ]]; then
  sed "/__COLLINS_INCLUDE__/r ${COLLINS_SNIPPET}" "$NGINX_CONF_DST" \
    | sed '/__COLLINS_INCLUDE__/d' >"${NGINX_CONF_DST}.merged"
  mv "${NGINX_CONF_DST}.merged" "$NGINX_CONF_DST"
  echo "edge-nginx-apply: included collins.d3bu7.com HTTPS vhost"
else
  sed '/__COLLINS_INCLUDE__/d' "$NGINX_CONF_DST" >"${NGINX_CONF_DST}.merged"
  mv "${NGINX_CONF_DST}.merged" "$NGINX_CONF_DST"
  echo "edge-nginx-apply: collins HTTPS vhost skipped (no LE cert for collins.d3bu7.com)"
fi

# YieldScope app + Supabase Kong (NodePorts 30082 / 30595)
yieldscope_ready=0
if { [[ -e "/etc/letsencrypt/live/yieldscope.d3bu7.com/fullchain.pem" ]] || [[ -L "/etc/letsencrypt/live/yieldscope.d3bu7.com/fullchain.pem" ]]; } \
  && { [[ -e "/etc/letsencrypt/live/supabase.yieldscope.d3bu7.com/fullchain.pem" ]] || [[ -L "/etc/letsencrypt/live/supabase.yieldscope.d3bu7.com/fullchain.pem" ]]; }; then
  yieldscope_ready=1
fi
if [[ "$yieldscope_ready" -eq 1 ]]; then
  install -m 644 "${EDGE_DIR}/nginx-yieldscope.conf" /etc/nginx/gitlab-edge/yieldscope.conf
  install -m 644 "${EDGE_DIR}/nginx-yieldscope-supabase.conf" /etc/nginx/gitlab-edge/yieldscope-supabase.conf
  sed 's|# __YIELDSCOPE_INCLUDE__|include /etc/nginx/gitlab-edge/yieldscope.conf;\n    include /etc/nginx/gitlab-edge/yieldscope-supabase.conf;|' \
    "$NGINX_CONF_DST" >"${NGINX_CONF_DST}.merged"
  mv "${NGINX_CONF_DST}.merged" "$NGINX_CONF_DST"
  echo "edge-nginx-apply: included yieldscope + supabase.yieldscope HTTPS vhosts"
else
  sed '/__YIELDSCOPE_INCLUDE__/d' "$NGINX_CONF_DST" >"${NGINX_CONF_DST}.merged"
  mv "${NGINX_CONF_DST}.merged" "$NGINX_CONF_DST"
  echo "edge-nginx-apply: yieldscope HTTPS vhosts skipped (no LE certs)"
fi

# mail.lilangverse.xyz + mail.yieldscope.d3bu7.com (fix wrong-SNI fallback to lip)
mail_https_ready=0
if [[ -f "${EDGE_DIR}/nginx-mail-https.conf" ]] \
  && { [[ -e "/etc/letsencrypt/live/mail.lilangverse.xyz/fullchain.pem" ]] || [[ -L "/etc/letsencrypt/live/mail.lilangverse.xyz/fullchain.pem" ]]; } \
  && { [[ -e "/etc/letsencrypt/live/mail.yieldscope.d3bu7.com/fullchain.pem" ]] || [[ -L "/etc/letsencrypt/live/mail.yieldscope.d3bu7.com/fullchain.pem" ]]; }; then
  mail_https_ready=1
fi
if [[ "$mail_https_ready" -eq 1 ]]; then
  install -m 644 "${EDGE_DIR}/nginx-mail-https.conf" /etc/nginx/gitlab-edge/nginx-mail-https.conf
  sed 's|# __MAIL_HTTPS_INCLUDE__|include /etc/nginx/gitlab-edge/nginx-mail-https.conf;|' \
    "$NGINX_CONF_DST" >"${NGINX_CONF_DST}.merged"
  mv "${NGINX_CONF_DST}.merged" "$NGINX_CONF_DST"
  echo "edge-nginx-apply: included mail.lilangverse + mail.yieldscope HTTPS vhosts"
else
  sed '/__MAIL_HTTPS_INCLUDE__/d' "$NGINX_CONF_DST" >"${NGINX_CONF_DST}.merged"
  mv "${NGINX_CONF_DST}.merged" "$NGINX_CONF_DST"
  echo "edge-nginx-apply: mail HTTPS vhosts skipped (no LE certs)"
fi
# Always install public HTTP front (landing :80 -> HTTPS + proxy to li-httpd :8080).
HTTP_FRONT="${EDGE_DIR}/nginx-obsevia-http-front.conf"
if [[ -f "$HTTP_FRONT" ]]; then
  install -m 644 "$HTTP_FRONT" /etc/nginx/gitlab-edge/nginx-obsevia-http-front.conf
  if ! grep -q 'nginx-obsevia-http-front.conf' "$NGINX_CONF_DST"; then
    sed -i '/include       \/etc\/nginx\/mime.types;/a\    include /etc/nginx/gitlab-edge/nginx-obsevia-http-front.conf;' "$NGINX_CONF_DST"
  fi
  echo "edge-nginx-apply: included HTTP :80 front"
else
  echo "edge-nginx-apply: WARN missing $HTTP_FRONT" >&2
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

BUREAUZILLA_SNIPPET="${EDGE_DIR}/nginx-bureauzilla.conf"
bureauzilla_cert_ready=0
if [[ -f "$BUREAUZILLA_SNIPPET" ]] && { [[ -e "/etc/letsencrypt/live/bureauzilla.com/fullchain.pem" ]] || [[ -L "/etc/letsencrypt/live/bureauzilla.com/fullchain.pem" ]]; }; then
  bureauzilla_cert_ready=1
fi
if [[ "$bureauzilla_cert_ready" -eq 1 ]]; then
  install -m 644 "$BUREAUZILLA_SNIPPET" /etc/nginx/gitlab-edge/nginx-bureauzilla.conf
  if grep -q "__BUREAUZILLA_INCLUDE__" "$NGINX_CONF_DST"; then
    sed "/__BUREAUZILLA_INCLUDE__/r ${BUREAUZILLA_SNIPPET}" "$NGINX_CONF_DST" \
      | sed "/__BUREAUZILLA_INCLUDE__/d" >"${NGINX_CONF_DST}.merged"
    mv "${NGINX_CONF_DST}.merged" "$NGINX_CONF_DST"
  else
    echo "    include /etc/nginx/gitlab-edge/nginx-bureauzilla.conf;" >> "$NGINX_CONF_DST"
  fi
  echo "edge-nginx-apply: included bureauzilla.com HTTPS vhost"
else
  if grep -q "__BUREAUZILLA_INCLUDE__" "$NGINX_CONF_DST"; then
    sed "/__BUREAUZILLA_INCLUDE__/d" "$NGINX_CONF_DST" >"${NGINX_CONF_DST}.merged"
    mv "${NGINX_CONF_DST}.merged" "$NGINX_CONF_DST"
  fi
  echo "edge-nginx-apply: bureauzilla HTTPS vhost skipped (no LE cert for bureauzilla.com)"
fi

export HOMELAB_LI_HTTPD_TLS_PORT=":8443"
bash "${SCRIPT_DIR}/edge-lis-apply.sh" --no-reload

systemctl stop li-httpd-homelab-tls.service 2>/dev/null || true
sleep 1

if systemctl is-enabled nginx-gitlab-edge.service &>/dev/null; then
  systemctl restart nginx-gitlab-edge.service
else
  systemctl enable --now nginx-gitlab-edge.service
fi
sleep 2
# Ensure workers picked up merged config (SNI vhosts).
systemctl reload nginx-gitlab-edge.service 2>/dev/null || true

systemctl restart li-httpd-homelab-tls.service

echo "edge-nginx-apply: done (nginx :443 GitLab prod, li-httpd-tls :8443 dev)"
ss -tlnp | grep -E ':443|:8443|:80 ' | head -20 || true
