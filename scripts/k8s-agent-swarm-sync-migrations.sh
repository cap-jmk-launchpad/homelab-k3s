#!/usr/bin/env bash
# Copy li-cursor-agents SQL migrations into the k8s bundle (run when migrations change).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-${LI_SRC:-$ROOT/../li}/li-cursor-agents/supabase/migrations}"
DEST="$ROOT/k8s/agent-swarm/db/migrations"
if [[ ! -d "$SRC" ]]; then
  echo "Usage: $0 [/path/to/supabase/migrations]" >&2
  exit 1
fi
mkdir -p "$DEST"
rsync -av --delete "$SRC/" "$DEST/"
echo "==> synced migrations to $DEST"
echo "    Re-run kustomize apply; migrate job applies new files only."
