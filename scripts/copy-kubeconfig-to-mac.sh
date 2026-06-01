#!/usr/bin/env bash
# Copy homelab kubeconfig to the Mac after key-based SSH works.
# Run from Windows (Git Bash) or blackpearl.
set -euo pipefail
MAC_USER="${MAC_USER:-julian}"
MAC_HOST="${MAC_HOST:-192.168.10.28}"
MAC_SSH="${MAC_USER}@${MAC_HOST}"
CP_HOST="${CP_HOST:-s4il0r@192.168.10.41}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/homelab}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -f "$REPO_ROOT/homelab" ]] && SSH_KEY="$REPO_ROOT/homelab"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

SSH_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
[[ -f "$SSH_KEY" ]] && SSH_OPTS+=(-i "$SSH_KEY")

scp "${SSH_OPTS[@]}" "$CP_HOST:.kube/config" "$TMP"
ssh "${SSH_OPTS[@]}" "$MAC_SSH" "mkdir -p ~/.kube && chmod 700 ~/.kube"
scp "${SSH_OPTS[@]}" "$TMP" "$MAC_SSH:.kube/config-homelab"
ssh "${SSH_OPTS[@]}" "$MAC_SSH" 'grep -q config-homelab ~/.zprofile 2>/dev/null || echo "export KUBECONFIG=\$HOME/.kube/config-homelab" >> ~/.zprofile'
echo "OK: ~/.kube/config-homelab on ${MAC_SSH}"
echo "On the Mac, open a new terminal and run: kubectl get nodes"
