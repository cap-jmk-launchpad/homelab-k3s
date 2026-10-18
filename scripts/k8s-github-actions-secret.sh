#!/usr/bin/env bash
# Create ARC github_token secrets for Majico, Librebase, and Obsevia org runners.
#
# Usage:
#   LAUNCHPAD_ENV=../.env ./scripts/k8s-github-actions-secret.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/scripts/lib/load-env.sh" ]]; then
  # shellcheck source=lib/load-env.sh
  source "$ROOT/scripts/lib/load-env.sh" "$ROOT"
fi

NS="${GITHUB_ACTIONS_NAMESPACE:-github-actions}"

kubectl apply -f "$ROOT/k8s/github-actions/namespace.yaml"

upsert_secret() {
  local name="$1"
  local token="$2"
  if [[ -z "$token" ]]; then
    echo "WARN: empty token for $name — skip (set env var or add to LAUNCHPAD_ENV)" >&2
    return 0
  fi
  kubectl -n "$NS" create secret generic "$name" \
    --from-literal=github_token="$token" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "secret/$name updated in namespace $NS"
}

upsert_secret majico-xyz-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_MAJICO:-}"
upsert_secret librebase-official-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_LIBREBASE:-}"
upsert_secret obsevia-compliance-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_OBSEVIA:-}"

echo "Done. Missing tokens? Add to launchpad .env:"
echo "  GITHUB_ACTIONS_RUNNER_TOKEN_MAJICO=..."
echo "  GITHUB_ACTIONS_RUNNER_TOKEN_LIBREBASE=..."
echo "  GITHUB_ACTIONS_RUNNER_TOKEN_OBSEVIA=..."
