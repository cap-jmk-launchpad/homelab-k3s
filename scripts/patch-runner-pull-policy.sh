#!/usr/bin/env bash
# One-shot: add pull_policy default to existing runner config.toml on PVC.
set -euo pipefail
NAMESPACE="${GITLAB_NAMESPACE:-gitlab}"
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1" >&2; exit 1; }; }
require_cmd kubectl

if kubectl exec -n "$NAMESPACE" deploy/gitlab-runner -- grep -q '^    pull_policy = ' /etc/gitlab-runner/config.toml 2>/dev/null; then
  echo "pull_policy already set"
  kubectl exec -n "$NAMESPACE" deploy/gitlab-runner -- grep -E 'pull_policy|allowed_pull' /etc/gitlab-runner/config.toml
  exit 0
fi

kubectl exec -n "$NAMESPACE" deploy/gitlab-runner -- sh -c \
  'sed -i "/allowed_pull_policies/a\\    pull_policy = \"if-not-present\"" /etc/gitlab-runner/config.toml'

kubectl rollout restart deployment/gitlab-runner -n "$NAMESPACE"
kubectl rollout status deployment/gitlab-runner -n "$NAMESPACE" --timeout=120s
kubectl exec -n "$NAMESPACE" deploy/gitlab-runner -- grep -E 'pull_policy|allowed_pull' /etc/gitlab-runner/config.toml
