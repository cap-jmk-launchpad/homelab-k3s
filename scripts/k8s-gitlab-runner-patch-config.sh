#!/usr/bin/env bash
# Ensure gitlab-runner PVC config.toml has kubernetes executor settings required by P0 jobs.
set -euo pipefail

NAMESPACE="${GITLAB_NAMESPACE:-gitlab}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1" >&2; exit 1; }; }
require_cmd kubectl

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOKEN="${RUNNER_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(kubectl exec -n "$NAMESPACE" deploy/gitlab-runner -- awk -F'"' '/^  token = /{print $2; exit}' /etc/gitlab-runner/config.toml 2>/dev/null || true)"
fi
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: set RUNNER_TOKEN or register runner first" >&2
  exit 1
fi
cat > /tmp/gitlab-runner-config.toml <<EOF
concurrent = 2
check_interval = 3
log_level = "info"
listen_address = ":9252"

[[runners]]
  name = "homelab-k8s"
  url = "http://gitlab.gitlab.svc.cluster.local"
  token = "${TOKEN}"
  executor = "kubernetes"
  run_untagged = true
  locked = false
  tag_list = ["homelab-k8s"]
  [runners.kubernetes]
    namespace = "gitlab"
    service_account = "gitlab-runner"
    helper_image = "registry.gitlab.com/gitlab-org/gitlab-runner/gitlab-runner-helper:x86_64-v17.11.4"
    helper_image_pull_policy = "if-not-present"
    allowed_pull_policies = ["always", "if-not-present"]
    [runners.kubernetes.node_selector]
      "kubernetes.io/arch" = "amd64"
EOF
export B64="$(base64 -w0 /tmp/gitlab-runner-config.toml)"
kubectl scale deployment/gitlab-runner -n "$NAMESPACE" --replicas=0
kubectl delete pod -n "$NAMESPACE" runner-cfg-write --ignore-not-found
kubectl run -n "$NAMESPACE" runner-cfg-write --restart=Never --image=busybox:1.36 \
  --overrides="$(B64="$B64" python3 - <<'PY'
import json, os
b64 = os.environ["B64"]
print(json.dumps({
  "spec": {
    "nodeSelector": {"kubernetes.io/hostname": "engine"},
    "containers": [{
      "name": "w",
      "image": "busybox:1.36",
      "command": ["sh", "-c", f"echo {b64} | base64 -d > /cfg/config.toml && wc -c /cfg/config.toml && cat /cfg/config.toml"],
      "volumeMounts": [{"name": "cfg", "mountPath": "/cfg"}],
    }],
    "volumes": [{"name": "cfg", "persistentVolumeClaim": {"claimName": "gitlab-runner-config"}}],
  }
}))
PY
)"
kubectl wait -n "$NAMESPACE" --for=condition=Ready pod/runner-cfg-write --timeout=60s || true
kubectl logs -n "$NAMESPACE" runner-cfg-write
kubectl delete pod -n "$NAMESPACE" runner-cfg-write --ignore-not-found

kubectl rollout restart deployment/gitlab-runner -n "$NAMESPACE"
kubectl rollout status deployment/gitlab-runner -n "$NAMESPACE" --timeout=120s
