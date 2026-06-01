#!/usr/bin/env bash
# Run once ON the Mac (login user, e.g. julian) so homelab + blackpearl can SSH without password.
# Requires: Remote Login enabled (System Settings → General → Sharing → Remote Login).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTH="$HOME/.ssh/authorized_keys"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$AUTH"
chmod 600 "$AUTH"
for keyfile in "$ROOT/homelab.pub" "$ROOT/scripts/blackpearl.pub"; do
  [[ -f "$keyfile" ]] || continue
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    grep -qxF "$line" "$AUTH" 2>/dev/null || echo "$line" >>"$AUTH"
  done <"$keyfile"
done
echo "Keys installed in $AUTH"
echo "Test from Windows:"
echo "  ssh -i /path/to/beelink-cleanup/homelab $(whoami)@$(ipconfig getifaddr en0 2>/dev/null || hostname) hostname"
echo "Test from blackpearl:"
echo "  ssh -i ~/.ssh/homelab $(whoami)@192.168.10.28 hostname"
