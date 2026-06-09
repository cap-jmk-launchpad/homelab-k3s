#!/usr/bin/env bash
# Apply GitLab CE + Runner (NodePort 30481). Separate namespace from supabase.
#
# Usage:
#   ./scripts/k8s-gitlab-apply.sh
#   GITLAB_REMOTE=1 STAGING_HOST=blackpearl ./scripts/k8s-gitlab-apply.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/scripts/lib/load-env.sh" ]]; then
  # shellcheck source=lib/load-env.sh
  source "$ROOT/scripts/lib/load-env.sh" "$ROOT"
fi

REMOTE="${GITLAB_REMOTE:-0}"
STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$ROOT/../blackpearl}"
REMOTE_DIR="${GITLAB_REMOTE_DIR:-$HOME/homelab-k3s}"
GITLAB_NAMESPACE="${GITLAB_NAMESPACE:-gitlab}"

require_secret() {
  kubectl get secret "$1" -n "$GITLAB_NAMESPACE" >/dev/null 2>&1 || {
    echo "ERROR: missing secret $1 — run scripts/k8s-gitlab-secret.sh first" >&2
    exit 1
  }
}

sync_remote() {
  command -v rsync >/dev/null 2>&1 || {
    echo "ERROR: rsync required for GITLAB_REMOTE=1" >&2
    exit 1
  }
  local ssh_opts=(-i "$STAGING_KEY" -o IdentitiesOnly=yes)
  local launchpad_env="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" "mkdir -p ${REMOTE_DIR}/k8s ${REMOTE_DIR}/scripts ~/launchpad"
  rsync -az \
    -e "ssh ${ssh_opts[*]}" \
    "$ROOT/k8s/gitlab/" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/gitlab/"
  rsync -az \
    -e "ssh ${ssh_opts[*]}" \
    "$ROOT/scripts/k8s-gitlab-secret.sh" \
    "$ROOT/scripts/k8s-gitlab-apply.sh" \
    "$ROOT/scripts/k8s-gitlab-backup.sh" \
    "$ROOT/scripts/k8s-gitlab-fix-ci-signing-keys.sh" \
    "$ROOT/scripts/k8s-gitlab-fix-project-runners-tokens.sh" \
    "$ROOT/scripts/k8s-gitlab-runner-patch-config.sh" \
    "$ROOT/scripts/import-gitlab-runner-helper-to-engine.sh" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/"
  if [[ -f "$launchpad_env" ]]; then
    rsync -az -e "ssh ${ssh_opts[*]}" "$launchpad_env" \
      "${STAGING_USER}@${STAGING_HOST}:~/launchpad/.env"
  fi
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" \
    "chmod +x ${REMOTE_DIR}/scripts/k8s-gitlab-*.sh"
}

apply_local() {
  require_secret gitlab-secrets
  echo "==> apply gitlab stack (namespace $GITLAB_NAMESPACE)"
  kubectl apply -k "$ROOT/k8s/gitlab/"

  echo "==> wait for gitlab (first boot may take 10–20 min)"
  kubectl -n "$GITLAB_NAMESPACE" rollout status statefulset/gitlab --timeout=1800s

  echo "==> wait for runner (after GitLab is healthy)"
  kubectl -n "$GITLAB_NAMESPACE" rollout status deployment/gitlab-runner --timeout=600s

  kubectl -n "$GITLAB_NAMESPACE" get pods,svc
  local np="${GITLAB_NODEPORT:-30481}"
  echo ""
  echo "NodePort:     http://<blackpearl-ip>:${np}/  (user: root)"
  echo "Port-forward: kubectl -n $GITLAB_NAMESPACE port-forward svc/gitlab 8080:80"
  echo "Runner:       kubernetes executor, namespace $GITLAB_NAMESPACE, tags k8s,homelab"
  echo ""
  echo "Optional WAN: set GITLAB_PUBLIC_URL + edge route in k8s/edge/homelab.httpd.toml, then edge-lis-apply"
}

if [[ "$REMOTE" == "1" ]]; then
  sync_remote
  ssh -i "$STAGING_KEY" -o IdentitiesOnly=yes "${STAGING_USER}@${STAGING_HOST}" bash -s <<EOF
set -euo pipefail
cd ${REMOTE_DIR}
export LAUNCHPAD_ENV="\${LAUNCHPAD_ENV:-\$HOME/launchpad/.env}"
./scripts/k8s-gitlab-secret.sh
ROOT="${REMOTE_DIR}" GITLAB_REMOTE=0 ./scripts/k8s-gitlab-apply.sh
EOF
else
  apply_local
fi
