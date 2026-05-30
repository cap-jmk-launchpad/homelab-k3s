#!/usr/bin/env bash
# Install homelab cluster SSH pubkey on this host (<admin-user> + optional root).
# Usage: sudo bash install-automation-key.sh <automation-pubkey-file>
set -euo pipefail

PUBKEY_FILE="${1:?Usage: $0 <automation-pubkey-file>}"
PUBKEY="$(tr -d '\r\n' <"$PUBKEY_FILE" | head -1)"
USER="${ADMIN_USER:?Set ADMIN_USER e.g. your automation account name}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo $0 $PUBKEY_FILE" >&2
  exit 1
fi

install_key() {
  local home="$1" owner="$2"
  install -d -m 700 -o "$owner" -g "$owner" "$home/.ssh"
  touch "$home/.ssh/authorized_keys"
  chmod 600 "$home/.ssh/authorized_keys"
  chown "$owner:$owner" "$home/.ssh/authorized_keys"
  grep -qxF "$PUBKEY" "$home/.ssh/authorized_keys" || echo "$PUBKEY" >>"$home/.ssh/authorized_keys"
}

if id "$USER" &>/dev/null; then
  install_key "/home/${USER}" "$USER"
else
  echo "User ${USER} does not exist. Set ADMIN_USER or create the user first." >&2
  exit 1
fi

if [[ "${INSTALL_ROOT_KEY:-0}" == "1" ]]; then
  install_key /root root
fi

echo "Installed automation pubkey for ${USER}"
