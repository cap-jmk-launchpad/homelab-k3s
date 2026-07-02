#!/usr/bin/env bash
# Download launchpad/.env from blackpearl (canonical homelab secrets store).
# Never prints secret values.
#
# Usage:
#   ./scripts/pull-launchpad-env.sh
#   OBSEVIA_SSH_KEY=~/.ssh/obsevia_homelab ./scripts/pull-launchpad-env.sh
#
# Local layout (see klaut-pro README):
#   launchpad/.env              <- downloaded secrets (gitignored)
#   launchpad/homelab-k3s/      <- this repo
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHPAD_ROOT="$(dirname "$ROOT")"
ENV_OUT="${LAUNCHPAD_ENV:-$LAUNCHPAD_ROOT/.env}"
REMOTE="${LAUNCHPAD_REMOTE:-${OBSEVIA_K8S_REMOTE:-s4il0r@192.168.10.33}}"
REMOTE_ENV="${LAUNCHPAD_REMOTE_ENV:-~/launchpad/.env}"
SSH_KEY="${OBSEVIA_SSH_KEY:-${SSH_KEY:-}}"

scp_cmd() {
  local opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
  [[ -n "$SSH_KEY" ]] && opts+=(-i "$SSH_KEY")
  scp "${opts[@]}" "$@"
}

usage() {
  cat <<'EOF'
Usage: scripts/pull-launchpad-env.sh [options]

Downloads ~/launchpad/.env from the homelab k3s node into launchpad/.env
(sibling of homelab-k3s). Secret values are never printed.

Options:
  --remote USER@HOST     SSH target (default: s4il0r@192.168.10.33)
  --remote-env PATH      Remote env path (default: ~/launchpad/.env)
  --env-out PATH         Local output (default: ../.env next to homelab-k3s)
  --ssh-key PATH         SSH identity file
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote) REMOTE="${2:?}"; shift 2 ;;
    --remote-env) REMOTE_ENV="${2:?}"; shift 2 ;;
    --env-out) ENV_OUT="${2:?}"; shift 2 ;;
    --ssh-key) SSH_KEY="${2:?}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "Downloading $REMOTE:$REMOTE_ENV -> $ENV_OUT"
scp_cmd "$REMOTE:$REMOTE_ENV" "$tmp"

mkdir -p "$(dirname "$ENV_OUT")"
python3 - "$tmp" "$ENV_OUT" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
text = src.read_text()
text = text.replace("\r\n", "\n").replace("\r", "\n")
if not text.endswith("\n"):
    text += "\n"
dst.write_text(text)
dst.chmod(0o600)
keys = sum(
    1
    for line in text.splitlines()
    if line.strip() and not line.lstrip().startswith("#") and "=" in line
)
print(f"Wrote {dst} ({keys} key(s)). Values were not printed.")
PY
