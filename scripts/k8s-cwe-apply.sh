#!/usr/bin/env bash
# Deploy MITRE CWE mirror (PVC + CronJob sync + nginx static API, NodePort 30483).
#
# Usage:
#   ./scripts/k8s-cwe-apply.sh
#   CWE_REMOTE=1 STAGING_HOST=blackpearl ./scripts/k8s-cwe-apply.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/scripts/lib/load-env.sh" ]]; then
  # shellcheck source=lib/load-env.sh
  source "$ROOT/scripts/lib/load-env.sh" "$ROOT"
fi

REMOTE="${CWE_REMOTE:-0}"
STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$ROOT/../blackpearl}"
REMOTE_DIR="${CWE_REMOTE_DIR:-$HOME/homelab-k3s}"
CWE_NAMESPACE="${CWE_NAMESPACE:-cwe}"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"

load_launchpad_env() {
  [[ -f "$LAUNCHPAD_ENV" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  sed '1s/^\xEF\xBB\xBF//; s/\r$//' "$LAUNCHPAD_ENV" >"$tmp"
  set -a
  # shellcheck disable=SC1090
  source "$tmp"
  set +a
  rm -f "$tmp"
}

load_launchpad_env

require_secret() {
  kubectl get secret "$1" -n "$CWE_NAMESPACE" >/dev/null 2>&1 || {
    echo "ERROR: missing secret $1 — run scripts/k8s-cwe-secret.sh first" >&2
    exit 1
  }
}

sync_remote() {
  command -v rsync >/dev/null 2>&1 || {
    echo "ERROR: rsync required for CWE_REMOTE=1" >&2
    exit 1
  }
  local ssh_opts=(-i "$STAGING_KEY" -o IdentitiesOnly=yes)
  local launchpad_env="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" \
    "mkdir -p ${REMOTE_DIR}/k8s/cwe ${REMOTE_DIR}/scripts ~/launchpad"
  rsync -az \
    -e "ssh ${ssh_opts[*]}" \
    "$ROOT/k8s/cwe/" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/cwe/"
  rsync -az \
    -e "ssh ${ssh_opts[*]}" \
    "$ROOT/scripts/k8s-cwe-secret.sh" \
    "$ROOT/scripts/k8s-cwe-apply.sh" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/"
  if [[ -f "$launchpad_env" ]]; then
    rsync -az -e "ssh ${ssh_opts[*]}" "$launchpad_env" \
      "${STAGING_USER}@${STAGING_HOST}:~/launchpad/.env"
  fi
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" \
    "chmod +x ${REMOTE_DIR}/scripts/k8s-cwe-*.sh"
}

run_initial_sync() {
  local job="cwe-mirror-init-$(date +%s)"
  echo "==> one-shot sync job ${job}"
  kubectl -n "$CWE_NAMESPACE" create job "$job" --from=cronjob/cwe-mirror-sync
  kubectl -n "$CWE_NAMESPACE" wait --for=condition=complete "job/${job}" --timeout=600s
}

apply_local() {
  require_secret cwe-mirror-secrets

  echo "==> apply cwe-mirror stack (namespace $CWE_NAMESPACE)"
  kubectl apply -k "$ROOT/k8s/cwe/"

  if [[ -n "${CWE_SYNC_SCHEDULE:-}" && "${CWE_SYNC_SCHEDULE}" != "*/10 * * * *" ]]; then
    kubectl -n "$CWE_NAMESPACE" patch cronjob cwe-mirror-sync \
      --type merge -p "{\"spec\":{\"schedule\":\"${CWE_SYNC_SCHEDULE}\"}}"
  fi

  kubectl -n "$CWE_NAMESPACE" rollout status deployment/cwe-mirror --timeout=120s

  run_initial_sync

  kubectl -n "$CWE_NAMESPACE" get pods,svc,cronjob
  local np="${CWE_NODEPORT:-30483}"
  echo ""
  echo "NodePort:     http://192.168.10.33:${np}/manifest.json"
  echo "In-cluster:   http://cwe-mirror.${CWE_NAMESPACE}.svc.cluster.local:8080/"
  echo "Optional WAN: cwe.klaut.pro — docs/cwe-homelab.md + k8s/edge/homelab.httpd.toml"
}

if [[ "$REMOTE" == "1" ]]; then
  sync_remote
  ssh -i "$STAGING_KEY" -o IdentitiesOnly=yes "${STAGING_USER}@${STAGING_HOST}" bash -s <<EOF
set -euo pipefail
cd ${REMOTE_DIR}
export LAUNCHPAD_ENV="\${LAUNCHPAD_ENV:-\$HOME/launchpad/.env}"
./scripts/k8s-cwe-secret.sh
ROOT="${REMOTE_DIR}" CWE_REMOTE=0 ./scripts/k8s-cwe-apply.sh
EOF
else
  apply_local
fi
