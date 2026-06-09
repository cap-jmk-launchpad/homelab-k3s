#!/usr/bin/env bash
# Ensure gitlab-runner PVC config.toml has kubernetes executor settings required by P0 jobs.
set -euo pipefail

NAMESPACE="${GITLAB_NAMESPACE:-gitlab}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1" >&2; exit 1; }; }
require_cmd kubectl

kubectl exec -n "$NAMESPACE" deploy/gitlab-runner -- sh -c '
set -eu
CFG=/etc/gitlab-runner/config.toml
if ! grep -q "allowed_pull_policies" "$CFG"; then
  sed -i "/service_account = \"gitlab-runner\"/a\\    allowed_pull_policies = [\"always\", \"if-not-present\"]" "$CFG"
fi
grep -A6 "\[runners.kubernetes\]" "$CFG"
'

kubectl rollout restart deployment/gitlab-runner -n "$NAMESPACE"
kubectl rollout status deployment/gitlab-runner -n "$NAMESPACE" --timeout=120s
