#!/usr/bin/env bash
# One-time access hardening for fresh blackpearl (Majico staging homelab).
# Run as root on the new Debian box after copying this repo (or just scripts/) to /root/setup/
#
#   curl -fsSL ...  OR  scp -r scripts/ root@blackpearl:/root/setup/
#   bash /root/setup/setup-blackpearl-access.sh
#
set -euo pipefail

STAGING_USER="${STAGING_USER:-s4il0r}"
HOSTNAME="${HOSTNAME:-blackpearl}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUTH_KEYS="${SCRIPT_DIR}/authorized_keys"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

if [[ ! -f "$AUTH_KEYS" ]]; then
  echo "Missing ${AUTH_KEYS} — copy scripts/authorized_keys from beelink-cleanup repo." >&2
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
  echo "Created ${STAGING_USER}. Set a console password if desired: passwd ${STAGING_USER}"
else
  usermod -aG sudo "$STAGING_USER" 2>/dev/null || true
fi

install -d -m 700 -o "$STAGING_USER" -g "$STAGING_USER" "/home/${STAGING_USER}/.ssh"
install -m 600 -o "$STAGING_USER" -g "$STAGING_USER" "$AUTH_KEYS" "/home/${STAGING_USER}/.ssh/authorized_keys"

echo "== passwordless sudo (automation user only) =="
install -d -m 750 /etc/sudoers.d
cat >"/etc/sudoers.d/${STAGING_USER}-nopasswd" <<EOF
# Majico staging automation — homelab only. Root SSH login remains disabled.
${STAGING_USER} ALL=(ALL:ALL) NOPASSWD:ALL
EOF
chmod 440 "/etc/sudoers.d/${STAGING_USER}-nopasswd"
visudo -cf /etc/sudoers.d/"${STAGING_USER}-nopasswd"

echo "== SSH hardening =="
install -d -m 755 /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-staging-automation.conf <<EOF
# Agent / Cursor automation — key-only for ${STAGING_USER}
Match User ${STAGING_USER}
    AuthenticationMethods publickey
    PubkeyAuthentication yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no

# Global defaults
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
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

echo "== hostname =="
hostnamectl set-hostname "$HOSTNAME" 2>/dev/null || echo "$HOSTNAME" >/etc/hostname

echo "== firewall (SSH only; add staging ports when ready) =="
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
# ufw allow 8080/tcp comment 'majico staging http'
# ufw allow 8443/tcp comment 'majico staging https'
ufw --force enable

echo "== staging directories =="
install -d -o "$STAGING_USER" -g "$STAGING_USER" \
  "/home/${STAGING_USER}/staging" \
  "/home/${STAGING_USER}/staging/majico.xyz" \
  "/home/${STAGING_USER}/staging/supabase"

echo "== podman rootless hint =="
loginctl enable-linger "$STAGING_USER" 2>/dev/null || true

echo "== always-on (no sleep/hibernate) =="
bash "${SCRIPT_DIR}/disable-sleep.sh"

echo ""
echo "Done. From your PC:"
echo "  ssh -i blackpearl ${STAGING_USER}@${HOSTNAME}"
echo "  ssh ${STAGING_USER}@${HOSTNAME} 'sudo whoami'   # should print root without password prompt"
echo ""
echo "Reboot to verify autologin on physical console (tty1)."
