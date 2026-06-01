#!/usr/bin/env bash
# Move homelab workloads off blackpearl (control plane) onto engine.
# Run on blackpearl with kubectl + helm. SigNoz ClickHouse PVCs are recreated (telemetry history reset).
set -euo pipefail

REPO_DIR="${REPO_DIR:-$HOME/staging/beelink-cleanup}"
MON_DIR="${REPO_DIR}/k8s/monitoring"
ENGINE=engine

echo "==> Helm: SigNoz (delete old blackpearl PVCs first)"
kubectl delete pod -n signoz --all --wait=true --ignore-not-found 2>/dev/null || true
kubectl delete pvc -n signoz --all --wait=true --ignore-not-found 2>/dev/null || true

helm repo add signoz https://charts.signoz.io 2>/dev/null || true
helm repo update
helm upgrade --install signoz signoz/signoz -n signoz \
  -f "${MON_DIR}/signoz-values.yaml" --wait --timeout 25m
helm upgrade --install signoz-k8s-infra signoz/k8s-infra -n signoz \
  -f "${MON_DIR}/signoz-k8s-infra-values.yaml" --wait --timeout 15m

echo "==> Helm: Prometheus stack (Grafana/Alertmanager/operator -> engine)"
GRAF_PW="$(kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || true)"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update
if [[ -n "${GRAF_PW}" ]]; then
  helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
    -n monitoring -f "${MON_DIR}/kube-prometheus-stack-values.yaml" \
    --set "grafana.adminPassword=${GRAF_PW}" --wait --timeout 15m
else
  helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
    -n monitoring -f "${MON_DIR}/kube-prometheus-stack-values.yaml" \
    --wait --timeout 15m
fi

patch_ns() {
  local ns=$1
  shift
  for kind in "$@"; do
    kubectl get "$kind" -n "$ns" -o name 2>/dev/null | while read -r obj; do
      kubectl patch "$obj" -n "$ns" --type merge -p \
        "{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${ENGINE}\"}}}}}" 2>/dev/null || \
      kubectl patch "$obj" -n "$ns" --type merge -p \
        "{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${ENGINE}\"}}}}}" 2>/dev/null || true
    done
  done
}

echo "==> Patch stateless / movable deployments to engine"
for dep in majico-app majico-worker supabase-auth supabase-kong supabase-rest; do
  kubectl patch deploy "$dep" -n majico-staging --type merge -p \
    "{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${ENGINE}\"}}}}}" 2>/dev/null || true
done
kubectl patch deploy high-fi-demos -n high-fi-demos --type merge -p \
  "{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${ENGINE}\"}}}}}" 2>/dev/null || true
kubectl patch deploy postgrest-proxy -n agent-swarm --type merge -p \
  "{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"${ENGINE}\"}}}}}" 2>/dev/null || true

echo "==> Restart majico/postgres/redis on engine (requires PVC delete if bound to blackpearl)"
echo "    Skip auto-migrate for postgres/redis — run manual pg_dump if you need data."

echo ""
echo "==> Pod placement"
kubectl get pods -A --field-selector spec.nodeName=blackpearl --no-headers | wc -l | xargs echo "pods still on blackpearl:"
kubectl top node 2>/dev/null || true
