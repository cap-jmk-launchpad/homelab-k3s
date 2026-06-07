#!/usr/bin/env bash
# Deploy Grafana dashboard ConfigMaps using any available cluster access path.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MON_DIR="${REPO_ROOT}/k8s/monitoring"
NS=monitoring
GRAF_URL="${GRAF_URL:-http://192.168.10.41:30300}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PW="${GRAFANA_PW:-HomelabGraf2026!}"
SSH_KEY="${SSH_KEY:-$REPO_ROOT/homelab}"
[[ -f "$SSH_KEY" ]] || SSH_KEY="$HOME/.ssh/homelab"
[[ -f "$SSH_KEY" ]] || SSH_KEY=""

deploy_cm() {
  local name="$1"
  local file="$2"
  kubectl create configmap "$name" \
    --from-file="${file%.json}.json=${MON_DIR}/${file}" \
    -n "$NS" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl label configmap "$name" -n "$NS" grafana_dashboard=1 --overwrite
  echo "Applied ConfigMap $name"
}

verify_dashboard() {
  python3 - <<PY
import json, urllib.request, base64, sys
uid = sys.argv[1]
creds = base64.b64encode("${GRAFANA_USER}:${GRAFANA_PW}".encode()).decode()
req = urllib.request.Request(
    "${GRAF_URL}/api/dashboards/uid/" + uid,
    headers={"Authorization": f"Basic {creds}"},
)
with urllib.request.urlopen(req, timeout=30) as resp:
    d = json.load(resp)
panel = next(p for p in d["dashboard"]["panels"] if p.get("id") == 112)
n = len(panel["fieldConfig"].get("overrides") or [])
print(f"uid={uid} version={d['dashboard'].get('version')} panel112_overrides={n} provisioned={d.get('meta',{}).get('provisioned')}")
if n < 5:
    raise SystemExit(f"expected >=5 node color overrides, got {n}")
PY
}

try_kubectl() {
  if [[ -n "${KUBECONFIG:-}" && -f "${KUBECONFIG}" ]]; then
    kubectl get nodes >/dev/null 2>&1 && return 0
  fi
  if kubectl get nodes >/dev/null 2>&1; then
    return 0
  fi
  for cfg in "$HOME/.kube/config-homelab" "$HOME/.kube/config" /etc/rancher/k3s/k3s.yaml; do
    [[ -f "$cfg" ]] || continue
    KUBECONFIG="$cfg" kubectl get nodes >/dev/null 2>&1 && { export KUBECONFIG="$cfg"; return 0; }
  done
  return 1
}

try_ssh_blackpearl() {
  [[ -n "$SSH_KEY" && -f "$SSH_KEY" ]] || return 1
  local remote="${STAGING_USER:-s4il0r}@${STAGING_HOST:-192.168.10.41}"
  local remote_repo="${REMOTE_REPO:-~/staging/beelink-cleanup}"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" "$remote" \
    "test -d $remote_repo/k8s/monitoring" 2>/dev/null || return 1
  echo "Deploying via SSH to $remote ..."
  rsync -az -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new" \
    "$MON_DIR/homelab-cluster-resources-dashboard.json" \
    "$MON_DIR/homelab-gpu-dashboard.json" \
    "$REPO_ROOT/scripts/homelab-deploy-dashboards.sh" \
    "$remote:$remote_repo/k8s/monitoring/" 2>/dev/null || true
  rsync -az -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=accept-new" \
    "$REPO_ROOT/scripts/homelab-deploy-dashboards.sh" \
    "$remote:$remote_repo/scripts/"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new "$remote" \
    "REPO_ROOT=$remote_repo bash $remote_repo/scripts/homelab-deploy-dashboards.sh"
  return 0
}

main() {
  if try_kubectl; then
    echo "Using kubectl (KUBECONFIG=${KUBECONFIG:-default})"
    deploy_cm homelab-cluster-resources-dashboard homelab-cluster-resources-dashboard.json
    deploy_cm homelab-gpu-dashboard homelab-gpu-dashboard.json
  elif try_ssh_blackpearl; then
    :
  else
    echo "No kubectl or SSH access to blackpearl." >&2
    echo "Place homelab SSH key at $REPO_ROOT/homelab or set KUBECONFIG." >&2
    return 1
  fi

  echo "Waiting for Grafana sidecar reload ..."
  sleep 15
  verify_dashboard homelab-cluster-resources
  echo "Done: ${GRAF_URL}/d/homelab-cluster-resources/homelab-cluster-resources"
}

main "$@"
