#!/usr/bin/env bash
# Deploy Ollama on engine from your PC (homelab SSH key).
# Usage (Git Bash / WSL / Linux / macOS):
#   bash scripts/engine-ollama-deploy.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_HOST="${ENGINE_HOST:-s4il0r@192.168.10.32}"
ENGINE_REPO="${ENGINE_REPO:-$HOME/beelink-cleanup}"
SSH_KEY="${SSH_KEY:-$ROOT/homelab}"
INSTALL="${ROOT}/scripts/engine-ollama-install.sh"

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
[[ -f "$SSH_KEY" ]] && SSH_OPTS+=(-i "$SSH_KEY")

[[ -f "$INSTALL" ]] || { echo "missing $INSTALL" >&2; exit 1; }

echo "==> sync install script to engine"
ssh "${SSH_OPTS[@]}" "$ENGINE_HOST" "mkdir -p ${ENGINE_REPO}/scripts"
scp "${SSH_OPTS[@]}" "$INSTALL" "${ENGINE_HOST}:${ENGINE_REPO}/scripts/engine-ollama-install.sh"

echo "==> run install on engine (GPU + model pull; may take several minutes)"
ssh -t "${SSH_OPTS[@]}" "$ENGINE_HOST" "bash ${ENGINE_REPO}/scripts/engine-ollama-install.sh"

echo "==> verify from this machine"
ENGINE_URL="${ENGINE_URL:-http://192.168.10.32:11434}"
curl -sf "${ENGINE_URL}/api/tags" | head -c 400
echo
echo "==> OK — OpenAI-compatible base: ${ENGINE_URL}/v1"
