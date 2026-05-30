#!/usr/bin/env bash
# Run once ON engine (as julian) so blackpearl + your PC can SSH without password.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTH="$HOME/.ssh/authorized_keys"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
touch "$AUTH"
chmod 600 "$AUTH"
for keyfile in "$ROOT/scripts/blackpearl.pub" "$ROOT/beelink.pub" "$ROOT/scripts/authorized_keys"; do
  [[ -f "$keyfile" ]] || continue
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    grep -qxF "$line" "$AUTH" 2>/dev/null || echo "$line" >>"$AUTH"
  done <"$keyfile"
done
echo "Keys installed in $AUTH"
echo "Test from blackpearl: ssh julian@$(hostname -I | awk '{print $1}') hostname"
