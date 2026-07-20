#!/usr/bin/env bash
# Edge MX router: one public :25 shared by li-mail / bureauzilla-mail / yieldscope-mail.
#
# Postfix on blackpearl accepts inbound SMTP for known domains and transports by
# RCPT domain to the matching k3s NodePort on loopback. This replaces the broken
# WAN DNAT to engine hostPorts (nothing listens on engine:25).
#
# Submission (:587) and IMAP (:143/:993) stay on per-tenant NodePorts via REDIRECT
# (default → li-mail). In-cluster Auth SMTP uses ClusterIP; e2e reads maildir via kubectl.
#
# Usage (root on blackpearl):
#   sudo bash scripts/edge-mail-mx-router-apply.sh
# Rollback:
#   sudo bash scripts/edge-mail-mx-router-apply.sh --rollback
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "edge-mail-mx-router-apply: run as root (sudo)" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF_DIR="/etc/postfix-mx-router"
TRANSPORT="${CONF_DIR}/transport"
MAIN_CF="${CONF_DIR}/main.cf"
MASTER_CF="${CONF_DIR}/master.cf"
UNIT="/etc/systemd/system/postfix-mx-router.service"

# NodePorts (loopback on blackpearl — kube-proxy)
LI_SMTP_NP="${LI_MAIL_SMTP_NODEPORT:-30525}"
LI_SUB_NP="${LI_MAIL_SUBMISSION_NODEPORT:-30587}"
LI_IMAP_NP="${LI_MAIL_IMAP_NODEPORT:-30143}"
LI_IMAPS_NP="${LI_MAIL_IMAPS_NODEPORT:-30593}"
BZ_SMTP_NP="${BUREAUZILLA_MAIL_SMTP_NODEPORT:-30725}"
YS_SMTP_NP="${YIELDSCOPE_MAIL_SMTP_NODEPORT:-30625}"

EDGE_IP="${MAIL_EDGE_IP:-192.168.10.33}"
ENGINE_IP="${MAIL_WIRE_HOST:-192.168.10.40}"

clear_engine_dnat() {
  local dport
  for dport in 25 587 143 993; do
    while iptables -t nat -D PREROUTING -p tcp --dport "$dport" -j DNAT --to-destination "${ENGINE_IP}:${dport}" 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -p tcp -d "$EDGE_IP" --dport "$dport" -j DNAT --to-destination "${ENGINE_IP}:${dport}" 2>/dev/null; do :; done
    while iptables -t nat -D POSTROUTING -p tcp -d "$ENGINE_IP" --dport "$dport" -j MASQUERADE 2>/dev/null; do :; done
    while iptables -D FORWARD -p tcp -d "$ENGINE_IP" --dport "$dport" -j ACCEPT 2>/dev/null; do :; done
  done
}

clear_redirects() {
  local dport np
  for dport in 25 587 143 993; do
    while iptables -t nat -D PREROUTING -p tcp --dport "$dport" -j REDIRECT 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -p tcp -m addrtype --dst-type LOCAL -m tcp --dport "$dport" -j REDIRECT 2>/dev/null; do :; done
    while iptables -t nat -D OUTPUT -d "$EDGE_IP" -p tcp -m tcp --dport "$dport" -j REDIRECT 2>/dev/null; do :; done
  done
  # Explicit known NodePort redirects (PREROUTING + OUTPUT)
  for np in "$LI_SMTP_NP" "$LI_SUB_NP" "$LI_IMAP_NP" "$LI_IMAPS_NP" "$BZ_SMTP_NP" "$YS_SMTP_NP" 30687 30693 30788 30793; do
    for dport in 25 587 143 993; do
      while iptables -t nat -D PREROUTING -p tcp --dport "$dport" -j REDIRECT --to-ports "$np" 2>/dev/null; do :; done
      while iptables -t nat -D OUTPUT -p tcp -m addrtype --dst-type LOCAL -m tcp --dport "$dport" -j REDIRECT --to-ports "$np" 2>/dev/null; do :; done
      while iptables -t nat -D OUTPUT -d "$EDGE_IP" -p tcp --dport "$dport" -j REDIRECT --to-ports "$np" 2>/dev/null; do :; done
    done
  done
}

add_redirect() {
  local dport="$1" np="$2"
  if iptables -t nat -C PREROUTING -p tcp --dport "$dport" -j REDIRECT --to-ports "$np" 2>/dev/null; then
    echo "keep REDIRECT tcp/$dport -> $np"
  else
    iptables -t nat -I PREROUTING 1 -p tcp --dport "$dport" -j REDIRECT --to-ports "$np"
    echo "add REDIRECT tcp/$dport -> $np"
  fi
}

rollback() {
  echo "==> rollback: stop MX router, restore li-mail NodePort REDIRECTs"
  systemctl stop postfix-mx-router 2>/dev/null || true
  systemctl disable postfix-mx-router 2>/dev/null || true
  clear_engine_dnat
  clear_redirects
  for p in 25 587 143 993; do
    ufw allow "${p}/tcp" comment 'li-mail-wire-wan' >/dev/null 2>&1 || true
  done
  add_redirect 25 "$LI_SMTP_NP"
  add_redirect 587 "$LI_SUB_NP"
  add_redirect 143 "$LI_IMAP_NP"
  add_redirect 993 "$LI_IMAPS_NP"
  echo "edge-mail-mx-router-apply: rolled back to li-mail NodePorts only"
}

if [[ "${1:-}" == "--rollback" ]]; then
  rollback
  exit 0
fi

echo "==> ensure postfix packages"
export DEBIAN_FRONTEND=noninteractive
if ! command -v postconf >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq postfix postfix-pcre
fi

echo "==> write isolated postfix-mx-router config in ${CONF_DIR}"
mkdir -p "$CONF_DIR" /var/spool/postfix-mx-router /var/lib/postfix-mx-router

# Dedicated queue dir (do not fight system postfix if present)
if [[ ! -d /var/spool/postfix-mx-router/pid ]]; then
  # Clone minimal spool structure from package defaults when available
  if [[ -d /var/spool/postfix ]]; then
    rsync -a --delete /var/spool/postfix/ /var/spool/postfix-mx-router/ 2>/dev/null || true
  fi
  mkdir -p /var/spool/postfix-mx-router/{pid,public,maildrop,incoming,active,deferred,bounce,corrupt,hold,trace,flush,saved,private}
fi
chown -R root:root /var/spool/postfix-mx-router
# postfix setgid bits are applied by postfix set-permissions when started

cat >"$TRANSPORT" <<EOF
# Domain → tenant SMTP NodePort on blackpearl loopback
bureauzilla.com           smtp:[127.0.0.1]:${BZ_SMTP_NP}
.bureauzilla.com          smtp:[127.0.0.1]:${BZ_SMTP_NP}
lilangverse.xyz           smtp:[127.0.0.1]:${LI_SMTP_NP}
.lilangverse.xyz          smtp:[127.0.0.1]:${LI_SMTP_NP}
yieldscope.d3bu7.com      smtp:[127.0.0.1]:${YS_SMTP_NP}
.yieldscope.d3bu7.com     smtp:[127.0.0.1]:${YS_SMTP_NP}
EOF
postmap "$TRANSPORT"

cat >"$MAIN_CF" <<EOF
# Multi-tenant WAN MX router (blackpearl edge) — no local mailboxes.
queue_directory = /var/spool/postfix-mx-router
command_directory = /usr/sbin
daemon_directory = /usr/lib/postfix/sbin
data_directory = /var/lib/postfix-mx-router
mail_owner = postfix
default_privs = nobody

myhostname = mx-edge.lilangverse.xyz
mydomain = lilangverse.xyz
myorigin = \$mydomain

inet_interfaces = all
inet_protocols = ipv4
mydestination =
local_recipient_maps =
local_transport = error:local delivery disabled on mx-edge

# Accept only our tenant domains; transport by RCPT domain.
relay_domains = bureauzilla.com, lilangverse.xyz, yieldscope.d3bu7.com
transport_maps = hash:${TRANSPORT}

smtpd_banner = \$myhostname ESMTP
smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination
smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination
mynetworks = 127.0.0.0/8 [::1]/128 192.168.10.0/24 10.42.0.0/16 10.43.0.0/16

message_size_limit = 52428800
mailbox_size_limit = 0
recipient_delimiter = +
compatibility_level = 3.6

# Do not rewrite recipients; pass through to backends.
receive_override_options = no_address_mappings
EOF

# Minimal master.cf: smtp inet + trivial rewrite/cleanup/qmgr/smtp client
cat >"$MASTER_CF" <<'EOF'
smtp      inet  n       -       y       -       -       smtpd
pickup    unix  n       -       y       60      1       pickup
cleanup   unix  n       -       y       -       0       cleanup
qmgr      unix  n       -       n       300     1       qmgr
tlsmgr    unix  -       -       y       1000?   1       tlsmgr
rewrite   unix  -       -       y       -       -       trivial-rewrite
bounce    unix  -       -       y       -       0       bounce
defer     unix  -       -       y       -       0       bounce
trace     unix  -       -       y       -       0       bounce
verify    unix  -       -       y       -       1       verify
flush     unix  n       -       y       1000?   0       flush
proxymap  unix  -       -       n       -       -       proxymap
proxywrite unix -       -       n       -       1       proxymap
smtp      unix  -       -       y       -       -       smtp
relay     unix  -       -       y       -       -       smtp
showq     unix  n       -       y       -       -       showq
error     unix  -       -       y       -       -       error
retry     unix  -       -       y       -       -       error
discard   unix  -       -       y       -       -       discard
local     unix  -       n       n       -       -       local
virtual   unix  -       n       n       -       -       virtual
lmtp      unix  -       -       y       -       -       lmtp
anvil     unix  -       -       y       -       1       anvil
scache    unix  -       -       y       -       1       scache
postlog   unix-dgram n  -       n       -       1       postlog
EOF

# Ensure system postfix (if any) does not own :25
if systemctl is-active --quiet postfix 2>/dev/null; then
  echo "==> stopping default postfix (replaced by postfix-mx-router on :25)"
  systemctl stop postfix || true
  systemctl disable postfix || true
fi

cat >"$UNIT" <<EOF
[Unit]
Description=Homelab multi-tenant MX router (Postfix)
Documentation=file://${ROOT}/docs/edge-mail-mx-router.md
After=network-online.target k3s.service
Wants=network-online.target

[Service]
Type=forking
PIDFile=/var/spool/postfix-mx-router/pid/master.pid
ExecStartPre=/usr/sbin/postfix -c ${CONF_DIR} check
ExecStart=/usr/sbin/postfix -c ${CONF_DIR} start
ExecReload=/usr/sbin/postfix -c ${CONF_DIR} reload
ExecStop=/usr/sbin/postfix -c ${CONF_DIR} stop
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> clear broken engine DNAT; bind :25 via postfix; REDIRECT 587/143/993 → li-mail"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
clear_engine_dnat
clear_redirects

for p in 25 587 143 993; do
  if command -v ufw >/dev/null 2>&1; then
    ufw allow "${p}/tcp" comment 'homelab-mail-wan' >/dev/null 2>&1 || true
  fi
done

# :25 served by postfix-mx-router (no REDIRECT)
add_redirect 587 "$LI_SUB_NP"
add_redirect 143 "$LI_IMAP_NP"
add_redirect 993 "$LI_IMAPS_NP"

postfix -c "$CONF_DIR" set-permissions 2>/dev/null || true
systemctl daemon-reload
systemctl enable postfix-mx-router
systemctl restart postfix-mx-router

sleep 1
if ! ss -tlnp | grep -q ':25 '; then
  echo "ERROR: nothing listening on :25 after start" >&2
  journalctl -u postfix-mx-router -n 40 --no-pager >&2 || true
  exit 1
fi

echo "edge-mail-mx-router-apply: OK"
echo "  :25  → postfix-mx-router → NodePorts ${LI_SMTP_NP}/${BZ_SMTP_NP}/${YS_SMTP_NP} by domain"
echo "  :587 → REDIRECT ${LI_SUB_NP} (li-mail; bureauzilla Auth uses ClusterIP/NodePort 30788)"
echo "  :993 → REDIRECT ${LI_IMAPS_NP} (li-mail; bureauzilla IMAP NodePort 30793 / kubectl maildir)"
echo "Rollback: sudo bash ${ROOT}/scripts/edge-mail-mx-router-apply.sh --rollback"
