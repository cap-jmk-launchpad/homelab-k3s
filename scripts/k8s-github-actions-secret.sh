#!/usr/bin/env bash
# Create ARC github_token secrets (one per GitHub org).
#
# Usage:
#   export KUBECONFIG=$HOME/.kube/config-homelab
#   LAUNCHPAD_ENV=../.env ./scripts/k8s-github-actions-secret.sh
#
# Or pass a single org token:
#   GITHUB_ACTIONS_RUNNER_TOKEN=ghp_... GITHUB_ACTIONS_RUNNER_ORG=majico-xyz ./scripts/k8s-github-actions-secret.sh
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

if [[ -n "${GITHUB_ACTIONS_RUNNER_TOKEN:-}" && -n "${GITHUB_ACTIONS_RUNNER_ORG:-}" ]]; then
  case "$GITHUB_ACTIONS_RUNNER_ORG" in
    cap-jmk-launchpad) upsert_secret cap-jmk-launchpad-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    majico-xyz) upsert_secret majico-xyz-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    librebase-official) upsert_secret librebase-official-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    obsevia-compliance) upsert_secret obsevia-compliance-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    sailblack) upsert_secret sailblack-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    taktwerk) upsert_secret taktwerk-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    *)
      echo "ERROR: unknown GITHUB_ACTIONS_RUNNER_ORG=$GITHUB_ACTIONS_RUNNER_ORG" >&2
      exit 1
      ;;
  esac
  exit 0
fi

upsert_secret cap-jmk-launchpad-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_CAP_JMK_LAUNCHPAD:-${GITHUB_ACTIONS_RUNNER_TOKEN_LAUNCHPAD:-}}"
upsert_secret majico-xyz-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_MAJICO:-}"
upsert_secret librebase-official-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_LIBREBASE:-}"
upsert_secret obsevia-compliance-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_OBSEVIA:-}"
upsert_secret sailblack-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_SAILBLACK:-}"
upsert_secret taktwerk-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_TAKTWERK:-}"

echo "Done. Per-org env vars (launchpad .env or export before re-run):"
echo "  GITHUB_ACTIONS_RUNNER_TOKEN_CAP_JMK_LAUNCHPAD / GITHUB_ACTIONS_RUNNER_TOKEN_LAUNCHPAD"
echo "  GITHUB_ACTIONS_RUNNER_TOKEN_MAJICO"
echo "  GITHUB_ACTIONS_RUNNER_TOKEN_LIBREBASE"
echo "  GITHUB_ACTIONS_RUNNER_TOKEN_OBSEVIA"
echo "  GITHUB_ACTIONS_RUNNER_TOKEN_SAILBLACK"
echo "  GITHUB_ACTIONS_RUNNER_TOKEN_TAKTWERK"
