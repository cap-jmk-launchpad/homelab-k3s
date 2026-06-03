#!/usr/bin/env bash
# Apply launchpad Supabase stack (internal NodePort 30480).
#
# Usage:
#   ./scripts/k8s-supabase-apply.sh
#   SUPABASE_REMOTE=1 STAGING_HOST=blackpearl ./scripts/k8s-supabase-apply.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh" "$ROOT"

REMOTE="${SUPABASE_REMOTE:-0}"
STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$ROOT/../blackpearl}"
REMOTE_DIR="${SUPABASE_REMOTE_DIR:-$HOME/homelab-k3s}"

require_secret() {
  kubectl get secret "$1" -n supabase >/dev/null 2>&1 || {
    echo "ERROR: missing secret $1 — run scripts/k8s-supabase-secret.sh first" >&2
    exit 1
  }
}

sync_remote() {
  command -v rsync >/dev/null 2>&1 || {
    echo "ERROR: rsync required for SUPABASE_REMOTE=1" >&2
    exit 1
  }
  local ssh_opts=(-i "$STAGING_KEY" -o IdentitiesOnly=yes)
  local launchpad_env="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" "mkdir -p ${REMOTE_DIR}/k8s ${REMOTE_DIR}/scripts/lib ~/launchpad"
  rsync -az \
    -e "ssh ${ssh_opts[*]}" \
    "$ROOT/k8s/supabase/" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/k8s/supabase/"
  rsync -az \
    -e "ssh ${ssh_opts[*]}" \
    "$ROOT/scripts/k8s-supabase-secret.sh" \
    "$ROOT/scripts/k8s-supabase-apply.sh" \
    "$ROOT/scripts/k8s-supabase-backup.sh" \
    "$ROOT/scripts/k8s-supabase-restore.sh" \
    "$ROOT/scripts/lib/k8s-supabase-keys.mjs" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/"
  rsync -az \
    -e "ssh ${ssh_opts[*]}" \
    "$ROOT/scripts/lib/k8s-supabase-keys.mjs" \
    "${STAGING_USER}@${STAGING_HOST}:${REMOTE_DIR}/scripts/lib/"
  if [[ -f "$launchpad_env" ]]; then
    rsync -az -e "ssh ${ssh_opts[*]}" "$launchpad_env" \
      "${STAGING_USER}@${STAGING_HOST}:~/launchpad/.env"
  fi
  ssh "${ssh_opts[@]}" "${STAGING_USER}@${STAGING_HOST}" \
    "chmod +x ${REMOTE_DIR}/scripts/k8s-supabase-*.sh"
}

apply_local() {
  require_secret supabase-secrets
  echo "==> apply supabase stack"
  kubectl apply -k "$ROOT/k8s/supabase/"

  echo "==> wait for postgres"
  kubectl -n supabase rollout status statefulset/db --timeout=600s

  if [[ -x "$ROOT/scripts/k8s-supabase-db-bootstrap.sh" ]]; then
    echo "==> bootstrap db role passwords"
    "$ROOT/scripts/k8s-supabase-db-bootstrap.sh"
  fi

  echo "==> run platform migrations"
  kubectl -n supabase delete job supabase-migrate --ignore-not-found
  kubectl apply -k "$ROOT/k8s/supabase/"
  kubectl -n supabase wait --for=condition=complete job/supabase-migrate --timeout=300s || true

  for dep in auth rest meta studio kong; do
    echo "==> wait $dep"
    kubectl -n supabase rollout status "deployment/$dep" --timeout=600s
  done

  kubectl -n supabase get pods,svc
  echo ""
  echo "NodePort API/Studio: http://<blackpearl-ip>:30480/"
  echo "Port-forward:       kubectl -n supabase port-forward svc/kong 54321:8000"
}

if [[ "$REMOTE" == "1" ]]; then
  sync_remote
  ssh -i "$STAGING_KEY" -o IdentitiesOnly=yes "${STAGING_USER}@${STAGING_HOST}" bash -s <<EOF
set -euo pipefail
cd ${REMOTE_DIR}
export LAUNCHPAD_ENV="\${LAUNCHPAD_ENV:-\$HOME/launchpad/.env}"
./scripts/k8s-supabase-secret.sh
ROOT="${REMOTE_DIR}" SUPABASE_REMOTE=0 ./scripts/k8s-supabase-apply.sh
EOF
else
  apply_local
fi
