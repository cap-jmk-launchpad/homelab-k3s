#!/usr/bin/env bash
# Complete blackpearl staging server prep. Run as root:
#   bash apply-server-prep.sh
# Or with pubkey file:
#   PUBKEY_FILE=/path/to/blackpearl.pub bash apply-server-prep.sh
set -euo pipefail

STAGING_USER="${STAGING_USER:-s4il0r}"
HOSTNAME="${HOSTNAME:-blackpearl}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBKEY_FILE="${PUBKEY_FILE:-${SCRIPT_DIR}/blackpearl.pub}"
AUTH_KEYS="${SCRIPT_DIR}/authorized_keys"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

if [[ -f "$PUBKEY_FILE" ]]; then
  PUBKEY="$(tr -d '\r\n' <"$PUBKEY_FILE" | head -1)"
elif [[ -f "$AUTH_KEYS" ]]; then
  PUBKEY="$(grep -m1 'blackpearl' "$AUTH_KEYS" || head -1 "$AUTH_KEYS")"
else
  echo "Missing pubkey: set PUBKEY_FILE or place blackpearl.pub in ${SCRIPT_DIR}" >&2
  exit 1
fi

echo "== packages =="
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  openssh-server sudo curl ca-certificates \
  podman podman-compose slirp4netns fuse-overlayfs \
  ufw

echo "== user ${STAGING_USER} =="
if ! id "$STAGING_USER" &>/dev/null; then
  useradd -m -s /bin/bash -G sudo,users "$STAGING_USER"
else
  usermod -aG sudo "$STAGING_USER" 2>/dev/null || true
fi

install -d -m 700 -o "$STAGING_USER" -g "$STAGING_USER" "/home/${STAGING_USER}/.ssh"
grep -qxF "$PUBKEY" "/home/${STAGING_USER}/.ssh/authorized_keys" 2>/dev/null || \
  echo "$PUBKEY" >>"/home/${STAGING_USER}/.ssh/authorized_keys"
chmod 600 "/home/${STAGING_USER}/.ssh/authorized_keys"
chown "$STAGING_USER:$STAGING_USER" "/home/${STAGING_USER}/.ssh/authorized_keys"

echo "== root SSH key (prohibit-password) =="
install -d -m 700 /root/.ssh
grep -qxF "$PUBKEY" /root/.ssh/authorized_keys 2>/dev/null || \
  echo "$PUBKEY" >>/root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

echo "== passwordless sudo for ${STAGING_USER} =="
install -d -m 750 /etc/sudoers.d
cat >"/etc/sudoers.d/${STAGING_USER}-nopasswd" <<EOF
${STAGING_USER} ALL=(ALL:ALL) NOPASSWD:ALL
EOF
chmod 440 "/etc/sudoers.d/${STAGING_USER}-nopasswd"
visudo -cf /etc/sudoers.d/"${STAGING_USER}-nopasswd"

echo "== SSH hardening =="
install -d -m 755 /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-staging-automation.conf <<EOF
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes

Match User ${STAGING_USER}
    AuthenticationMethods publickey
    PubkeyAuthentication yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no
EOF
sshd -t
systemctl enable --now ssh
systemctl reload ssh

echo "== console autologin (${STAGING_USER} on tty1) =="
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat >/etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${STAGING_USER} --noclear %I \$TERM
EOF
systemctl daemon-reload

echo "== always-on (no sleep) =="
bash "${SCRIPT_DIR}/disable-sleep.sh"

echo "== hostname =="
hostnamectl set-hostname "$HOSTNAME" 2>/dev/null || echo "$HOSTNAME" >/etc/hostname

echo "== firewall =="
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw --force enable

echo "== staging directories =="
install -d -m 700 -o "$STAGING_USER" -g "$STAGING_USER" "/home/${STAGING_USER}/staging/secrets"`ninstall -d -o "$STAGING_USER" -g "$STAGING_USER" \
  "/home/${STAGING_USER}/staging" \
  "/home/${STAGING_USER}/staging/supabase" \
  "/home/${STAGING_USER}/staging/majico.xyz" \
  "/home/${STAGING_USER}/staging/lic"`n  "/home/${STAGING_USER}/staging/lis-httpd"
loginctl enable-linger "$STAGING_USER" 2>/dev/null || true

echo ""
echo "Prep complete."
echo "Verify from PC:"
echo "  ssh -i blackpearl ${STAGING_USER}@${HOSTNAME} 'sudo -n id'"
echo "  ssh -i blackpearl root@${HOSTNAME} id"
echo "  ssh -i blackpearl ${STAGING_USER}@${HOSTNAME} 'systemctl is-enabled sleep.target'"
