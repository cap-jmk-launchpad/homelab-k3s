#!/usr/bin/env bash
# Deploy Caddy WAN edge on blackpearl (:80 + :443 → k3s NodePorts on 127.0.0.1).
# Prerequisite: Fritz!Box TCP 80,443 → 192.168.10.33; DNS A records → WAN IP.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EDGE_DIR="${REPO_ROOT}/k8s/edge"
SRC="${EDGE_DIR}/Caddyfile"
DEST="/etc/caddy/Caddyfile"
LE_SEARCH="/etc/letsencrypt/live/search.klaut.pro"
KLaut_CERT="/etc/caddy/certs-klaut/fullchain.pem"

usage() {
  echo "usage: edge-caddy-apply.sh [--certbot-search] [--dry-run]"
  echo "  --certbot-search  run certbot standalone for search.klaut.pro (needs WAN :80 forward)"
  exit 0
}

CERTBOT=0
DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --certbot-search) CERTBOT=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$SRC" ]] || { echo "missing $SRC" >&2; exit 1; }

if [[ "$CERTBOT" -eq 1 ]]; then
  if ss -tln | grep -q ':80 '; then
    echo "stopping caddy for certbot standalone (brief downtime)"
    sudo systemctl stop caddy
    NEED_START=1
  fi
  sudo certbot certonly --standalone --non-interactive --agree-tos \
    -m "${HOMELAB_ACME_EMAIL:-admin@majico.xyz}" -d search.klaut.pro \
    || { echo "certbot failed (is Fritz TCP 80 → 192.168.10.33 open?)" >&2; exit 1; }
  [[ "${NEED_START:-0}" -eq 1 ]] && sudo systemctl start caddy || true
fi

TMP="$(mktemp)"
cp "$SRC" "$TMP"

if [[ -f "${LE_SEARCH}/fullchain.pem" ]]; then
  sudo install -d -m 750 -o caddy -g caddy /etc/caddy/certs-klaut
  sudo cp -L "${LE_SEARCH}/fullchain.pem" "${LE_SEARCH}/privkey.pem" /etc/caddy/certs-klaut/
  sudo chown caddy:caddy /etc/caddy/certs-klaut/fullchain.pem /etc/caddy/certs-klaut/privkey.pem
  sudo chmod 644 /etc/caddy/certs-klaut/fullchain.pem
  sudo chmod 640 /etc/caddy/certs-klaut/privkey.pem
  cat >>"$TMP" <<'EOF'

search.klaut.pro {
	tls /etc/caddy/certs-klaut/fullchain.pem /etc/caddy/certs-klaut/privkey.pem
	reverse_proxy 127.0.0.1:30479
}
EOF
  echo "edge-caddy-apply: enabling HTTPS for search.klaut.pro (LE cert synced to /etc/caddy/certs-klaut)"
else
  echo "edge-caddy-apply: search HTTPS skipped — no ${LE_SEARCH}/fullchain.pem (HTTP on :80 only until certbot)" >&2
fi

if [[ "$DRY" -eq 1 ]]; then
  echo "--- $DEST (dry-run) ---"
  cat "$TMP"
  rm -f "$TMP"
  exit 0
fi

sudo install -d -m 755 /etc/caddy
sudo cp "$TMP" "$DEST"
rm -f "$TMP"
sudo caddy fmt --overwrite "$DEST" 2>/dev/null || true
if [[ -f "${LE_SEARCH}/fullchain.pem" ]]; then
  HOOK="/etc/letsencrypt/renewal-hooks/deploy/edge-caddy-sync-certs.sh"
  sudo tee "$HOOK" >/dev/null <<EOF
#!/bin/sh
exec bash ${REPO_ROOT}/scripts/edge-caddy-apply.sh
EOF
  sudo chmod 755 "$HOOK"
fi

sudo systemctl enable caddy
sudo systemctl reload caddy 2>/dev/null || sudo systemctl restart caddy
echo "edge-caddy-apply: reloaded caddy ($(systemctl is-active caddy))"

ss -tln | grep -E ':80 |:443 ' || true
echo "Test: curl -sS http://127.0.0.1/healthz -H 'Host: search.klaut.pro'"
curl -sS -o /dev/null -w 'local http search %{http_code}\n' http://127.0.0.1/healthz -H 'Host: search.klaut.pro' || true
if [[ -f "$KLaut_CERT" ]]; then
  curl -sk -o /dev/null -w 'local https search %{http_code}\n' https://127.0.0.1/healthz -H 'Host: search.klaut.pro' || true
fi
