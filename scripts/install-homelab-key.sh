#!/usr/bin/env bash
# Install homelab cluster SSH pubkey on this host (s4il0r + root). Run as root.
set -euo pipefail
PUBKEY_FILE="${1:?Usage: $0 /path/to/homelab.pub}"
PUBKEY="$(tr -d '\r\n' <"$PUBKEY_FILE" | head -1)"
USER="${STAGING_USER:-s4il0r}"

install_key() {
  local home="$1" owner="$2"
  install -d -m 700 -o "$owner" -g "$owner" "$home/.ssh"
  touch "$home/.ssh/authorized_keys"
  chmod 600 "$home/.ssh/authorized_keys"
  chown "$owner:$owner" "$home/.ssh/authorized_keys"
  grep -qxF "$PUBKEY" "$home/.ssh/authorized_keys" || echo "$PUBKEY" >>"$home/.ssh/authorized_keys"
}

install_key "/home/${USER}" "$USER"
install_key /root root
echo "Installed homelab pubkey for ${USER} and root"
