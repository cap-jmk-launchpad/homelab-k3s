#!/usr/bin/env bash
# Deploy Librebase todo-app to the homelab k3s cluster (engine node, amd64).
#
# 1. Syncs librebase sources to engine, builds docker.io/library/librebase-todo:latest
#    (sideload: imagePullPolicy=Never on the deployment).
# 2. Applies k8s/librebase-todo/todo-app.yaml (Namespace, ConfigMap, Deployment, NodePort :30585).
#
# Prereqs: ssh key ~/.ssh/homelab to s4il0r@engine (192.168.10.40), KUBECONFIG for the cluster.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="s4il0r@192.168.10.40"
SSH_KEY="${HOME}/.ssh/homelab"
SSH=(-i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=no)

LIBREBASE_REPO="${LIBREBASE_REPO:-${REPO_ROOT}/../../li-langverse-gitlab/li-langverse/librebase}"
REMOTE_DIR="~/staging/librebase-todo"

echo "==> sync librebase sources to engine"
ssh "${SSH[@]}" "$ENGINE" "mkdir -p $REMOTE_DIR/apps $REMOTE_DIR/packages $REMOTE_DIR/deploy"
rsync -az -e "ssh ${SSH[*]}" --exclude node_modules --exclude .git --exclude .next \
  "$LIBREBASE_REPO/apps/todo-app/" "$ENGINE:$REMOTE_DIR/apps/todo-app/"
rsync -az -e "ssh ${SSH[*]}" --exclude node_modules --exclude .git \
  "$LIBREBASE_REPO/packages/sdk/" "$ENGINE:$REMOTE_DIR/packages/sdk/"
rsync -az -e "ssh ${SSH[*]}" --exclude __pycache__ \
  "$LIBREBASE_REPO/../../lis/" "$ENGINE:$REMOTE_DIR/lis/"

echo "==> build image on engine (amd64)"
ssh "${SSH[@]}" "$ENGINE" "cd $REMOTE_DIR && \
  sudo docker build -t docker.io/library/librebase-todo:latest -f deploy/docker/librebase-todo/Dockerfile ."

echo "==> apply k8s manifests"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config-homelab}" kubectl apply -f "$REPO_ROOT/k8s/librebase-todo/todo-app.yaml"

echo "==> rollout status"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config-homelab}" kubectl -n librebase rollout status deployment/todo-app --timeout=180s

echo "==> done. todo-app → http://192.168.10.33:30585 (NodePort) / http://192.168.10.40:30585"
