#!/usr/bin/env bash
# Sideload gitlab-runner-helper:x86_64-v17.11.4 onto engine k3s containerd.
set -euo pipefail

VERSION="${VERSION:-v17.11.4}"
ARCH_TAG="${ARCH_TAG:-x86_64}"
IMAGE="registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:${ARCH_TAG}-${VERSION}"
TAR="${TAR:-/tmp/gitlab-runner-helper-${VERSION}.tar}"
IMPORT_PORT="${IMPORT_PORT:-18765}"
BLACKPEARL="${BLACKPEARL:-192.168.10.33}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/homelab}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config-homelab}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1" >&2; exit 1; }; }
require_cmd docker
require_cmd kubectl
require_cmd scp
require_cmd ssh

echo "==> Ensure helper image exists locally on blackpearl"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "s4il0r@${BLACKPEARL}" \
  "docker image inspect '${IMAGE}' >/dev/null 2>&1 || docker pull '${IMAGE}'"

echo "==> Create tarball on blackpearl"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "s4il0r@${BLACKPEARL}" \
  "docker save '${IMAGE}' -o '${TAR}' && ls -lh '${TAR}'"

echo "==> Serve tarball from blackpearl:${IMPORT_PORT}"
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "s4il0r@${BLACKPEARL}" \
  "pkill -f 'python3 -m http.server ${IMPORT_PORT}' 2>/dev/null || true; cd /tmp && nohup python3 -m http.server ${IMPORT_PORT} >/tmp/import-http-${IMPORT_PORT}.log 2>&1 & sleep 1 && curl -sfI http://127.0.0.1:${IMPORT_PORT}/$(basename "${TAR}") | head -1"

echo "==> Apply import job on engine"
kubectl --kubeconfig "$KUBECONFIG" delete job -n gitlab import-gitlab-runner-helper --ignore-not-found
kubectl --kubeconfig "$KUBECONFIG" apply -f "$(dirname "$0")/../k8s/gitlab/job-import-runner-helper.yaml"
kubectl --kubeconfig "$KUBECONFIG" wait -n gitlab --for=condition=complete job/import-gitlab-runner-helper --timeout=300s
kubectl --kubeconfig "$KUBECONFIG" logs -n gitlab job/import-gitlab-runner-helper

echo "==> Done — helper image imported on engine"
