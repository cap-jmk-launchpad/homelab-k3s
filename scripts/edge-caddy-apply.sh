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
ACME_EMAIL="${HOMELAB_ACME_EMAIL:-admin@majico.xyz}"

# host:upstream (empty upstream = TLS-only placeholder; HTTP block must exist in Caddyfile)
KLaut_HTTPS_HOSTS=(
  "search.klaut.pro:127.0.0.1:30479"
  "gitlab.klaut.pro:127.0.0.1:30481"
  "deps.klaut.pro:127.0.0.1:30482"
  "cwe.klaut.pro:127.0.0.1:30483"
  "vault.klaut.pro:"
)

KLaut_CERTBOT_DOMAINS=(
  search.klaut.pro
  gitlab.klaut.pro
  deps.klaut.pro
  cwe.klaut.pro
  vault.klaut.pro
)

usage() {
  echo "usage: edge-caddy-apply.sh [--certbot-search] [--certbot-klaut] [--dry-run]"
  echo "  --certbot-search  certbot standalone for search.klaut.pro only (legacy)"
  echo "  --certbot-klaut   certbot standalone for all klaut WAN hostnames missing LE certs"
  exit 0
}

sync_klaut_cert() {
  local host="$1"
  local le="/etc/letsencrypt/live/${host}"
  local dest
  if [[ "$host" == "search.klaut.pro" ]]; then
    dest="/etc/caddy/certs-klaut"
  else
    dest="/etc/caddy/certs-klaut/${host}"
  fi
  [[ -f "${le}/fullchain.pem" ]] || return 1
  sudo install -d -m 750 -o caddy -g caddy "$dest"
  sudo cp -L "${le}/fullchain.pem" "${le}/privkey.pem" "$dest/"
  sudo chown caddy:caddy "${dest}/fullchain.pem" "${dest}/privkey.pem"
  sudo chmod 644 "${dest}/fullchain.pem"
  sudo chmod 640 "${dest}/privkey.pem"
}

append_https_blocks() {
  local entry host upstream le cert_dir
  for entry in "${KLaut_HTTPS_HOSTS[@]}"; do
    host="${entry%%:*}"
    upstream="${entry#*:}"
    le="/etc/letsencrypt/live/${host}"
    if [[ ! -f "${le}/fullchain.pem" ]]; then
      echo "edge-caddy-apply: ${host} HTTPS skipped — no ${le}/fullchain.pem" >&2
      continue
    fi
    sync_klaut_cert "$host" || continue
    if [[ "$host" == "search.klaut.pro" ]]; then
      cert_dir="/etc/caddy/certs-klaut"
    else
      cert_dir="/etc/caddy/certs-klaut/${host}"
    fi
    if [[ -n "$upstream" ]]; then
      cat >>"$TMP" <<EOF

${host} {
	tls ${cert_dir}/fullchain.pem ${cert_dir}/privkey.pem
	reverse_proxy ${upstream}
}
EOF
    else
      cat >>"$TMP" <<EOF

${host} {
	tls ${cert_dir}/fullchain.pem ${cert_dir}/privkey.pem
	import /etc/caddy/vault-klaut-health.caddy
	root * /var/lib/caddy/vault-klaut
	file_server
}
EOF
    fi
    echo "edge-caddy-apply: enabling HTTPS for ${host}"
  done
}

CERTBOT=0
CERTBOT_KLAUT=0
DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --certbot-search) CERTBOT=1; shift ;;
    --certbot-klaut) CERTBOT_KLAUT=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -f "$SRC" ]] || { echo "missing $SRC" >&2; exit 1; }

run_certbot_standalone() {
  local -a domains=("$@")
  local d
  if ss -tln | grep -q ':80 '; then
    echo "stopping caddy for certbot standalone (brief downtime)"
    sudo systemctl stop caddy
    NEED_START=1
  fi
  for d in "${domains[@]}"; do
    if [[ -f "/etc/letsencrypt/live/${d}/fullchain.pem" ]]; then
      echo "edge-caddy-apply: LE cert already present for ${d}"
      continue
    fi
    echo "edge-caddy-apply: certbot ${d}"
    sudo certbot certonly --standalone --non-interactive --agree-tos \
      -m "${ACME_EMAIL}" -d "${d}" \
      || { echo "certbot failed for ${d} (is Fritz TCP 80 → 192.168.10.33 open?)" >&2; exit 1; }
  done
  [[ "${NEED_START:-0}" -eq 1 ]] && sudo systemctl start caddy || true
}

if [[ "$CERTBOT" -eq 1 ]]; then
  run_certbot_standalone search.klaut.pro
fi

if [[ "$CERTBOT_KLAUT" -eq 1 ]]; then
  run_certbot_standalone "${KLaut_CERTBOT_DOMAINS[@]}"
fi

if [[ -x "${REPO_ROOT}/scripts/edge-vault-klaut-status.sh" ]]; then
  sudo REPO_ROOT="$REPO_ROOT" "${REPO_ROOT}/scripts/edge-vault-klaut-status.sh" || true
fi

TMP="$(mktemp)"
cp "$SRC" "$TMP"
append_https_blocks

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

if compgen -G "/etc/letsencrypt/live/*.klaut.pro" >/dev/null 2>&1 || [[ -f "${LE_SEARCH}/fullchain.pem" ]]; then
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
for probe in \
  "search.klaut.pro|/healthz" \
  "gitlab.klaut.pro|/users/sign_in" \
  "deps.klaut.pro|/" \
  "cwe.klaut.pro|/health" \
  "vault.klaut.pro|/"; do
  host="${probe%%|*}"
  path="${probe#*|}"
  curl -sS -o /dev/null -w "local http ${host} %{http_code}\n" "http://127.0.0.1${path}" -H "Host: ${host}" || true
  if [[ -f "/etc/letsencrypt/live/${host}/fullchain.pem" ]]; then
    curl -sk -o /dev/null -w "local https ${host} %{http_code}\n" "https://127.0.0.1${path}" -H "Host: ${host}" || true
  fi
done
