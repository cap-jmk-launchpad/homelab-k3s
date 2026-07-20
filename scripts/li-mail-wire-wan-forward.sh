#!/usr/bin/env bash
# WAN TCP forward for mail ports on blackpearl.
#
# Prefer the multi-tenant MX router for :25 (domain → NodePort). This script is
# kept for rollback / li-mail-only mode and for submission/IMAP REDIRECTs when
# the MX router is not installed.
#
# Recommended:
#   sudo bash scripts/edge-mail-mx-router-apply.sh
#
# Legacy li-mail-only (breaks bureauzilla/yieldscope inbound MX):
#   sudo MAIL_MODE=li-mail-only bash scripts/li-mail-wire-wan-forward.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${MAIL_MODE:-mx-router}"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "li-mail-wire-wan-forward: run as root (sudo)" >&2
  exit 1
fi

if [[ "$MODE" == "mx-router" ]]; then
  echo "li-mail-wire-wan-forward: delegating to edge-mail-mx-router-apply.sh"
  exec bash "${ROOT}/scripts/edge-mail-mx-router-apply.sh" "$@"
fi

SMTP_NP="${MAIL_SMTP_NODEPORT:-30525}"
SUB_NP="${MAIL_SUBMISSION_NODEPORT:-30587}"
IMAP_NP="${MAIL_IMAP_NODEPORT:-30143}"
IMAPS_NP="${MAIL_IMAPS_NODEPORT:-30593}"
EDGE_IP="${MAIL_EDGE_IP:-192.168.10.33}"
ENGINE_IP="${MAIL_WIRE_HOST:-192.168.10.40}"

# Drop broken engine hostPort DNATs if present
for dport in 25 587 143 993; do
  while iptables -t nat -D PREROUTING -p tcp --dport "$dport" -j DNAT --to-destination "${ENGINE_IP}:${dport}" 2>/dev/null; do :; done
  while iptables -t nat -D OUTPUT -p tcp -d "$EDGE_IP" --dport "$dport" -j DNAT --to-destination "${ENGINE_IP}:${dport}" 2>/dev/null; do :; done
done

add_redirect() {
  local dport="$1" np="$2"
  if iptables -t nat -C PREROUTING -p tcp --dport "$dport" -j REDIRECT --to-ports "$np" 2>/dev/null; then
    echo "keep REDIRECT tcp/$dport -> $np"
  else
    iptables -t nat -I PREROUTING 1 -p tcp --dport "$dport" -j REDIRECT --to-ports "$np"
    echo "add REDIRECT tcp/$dport -> $np"
  fi
}

for p in 25 587 143 993; do
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${p}/tcp" comment 'li-mail-wire-wan' >/dev/null 2>&1 || true
  fi
done

add_redirect 25 "$SMTP_NP"
add_redirect 587 "$SUB_NP"
add_redirect 143 "$IMAP_NP"
add_redirect 993 "$IMAPS_NP"

echo "li-mail-wire-wan-forward: OK (li-mail-only 25->$SMTP_NP 587->$SUB_NP 143->$IMAP_NP 993->$IMAPS_NP)"
