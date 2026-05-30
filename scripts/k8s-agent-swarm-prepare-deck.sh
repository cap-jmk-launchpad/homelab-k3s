#!/usr/bin/env bash
# Sync li-langverse to Raspberry Pi deck and build li-cursor-agents on the host.
#
# Usage:
#   LI_SRC=/path/to/li-langverse ./scripts/k8s-agent-swarm-prepare-deck.sh
#   DECK_HOST=s4il0r@192.168.10.26 DECK_SSH_KEY=~/.ssh/homelab ./scripts/...
#
set -euo pipefail

DECK_HOST="${DECK_HOST:-s4il0r@192.168.10.26}"
DECK_SSH_KEY="${DECK_SSH_KEY:-$HOME/.ssh/homelab}"
DECK_ROOT="${DECK_ROOT:-/home/s4il0r/li-langverse}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LI_SRC="${LI_SRC:-$(cd "$SCRIPT_DIR/../../li" 2>/dev/null && pwd || true)}"

if [[ -z "$LI_SRC" || ! -d "$LI_SRC/li-cursor-agents" ]]; then
  echo "Set LI_SRC to the li-langverse directory (contains li-cursor-agents/)." >&2
  exit 1
fi

SSH=(ssh -o BatchMode=yes)
[[ -f "$DECK_SSH_KEY" ]] && SSH+=(-i "$DECK_SSH_KEY")
RSYNC_SSH="ssh -o BatchMode=yes"
[[ -f "$DECK_SSH_KEY" ]] && RSYNC_SSH="ssh -i $DECK_SSH_KEY -o BatchMode=yes"

echo "==> deck: ensure $DECK_ROOT"
"${SSH[@]}" "$DECK_HOST" "mkdir -p '$DECK_ROOT'"

echo "==> rsync li-langverse (no node_modules, no data/workspaces)"
rsync -avz --delete \
  -e "$RSYNC_SSH" \
  --exclude '.git/objects' \
  --exclude 'node_modules' \
  --exclude 'data/workspaces' \
  --exclude 'dist' \
  "$LI_SRC/" "$DECK_HOST:$DECK_ROOT/"

echo "==> deck: npm ci + build (arm64)"
"${SSH[@]}" "$DECK_HOST" bash -lc "
  set -euo pipefail
  command -v node >/dev/null || { echo 'Install Node 22 on deck first'; exit 1; }
  cd '$DECK_ROOT/li-cursor-agents'
  npm ci
  npm run build
  test -f dist/cli/serve-dashboard.js
  echo OK: dist ready on deck
"

echo ""
echo "Next: ./scripts/k8s-agent-swarm-secret.sh $LI_SRC/li-cursor-agents/.env"
echo "      ./scripts/k8s-agent-swarm-apply-deck.sh"
