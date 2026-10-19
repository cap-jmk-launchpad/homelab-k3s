#!/usr/bin/env bash
# Create ARC github_token secrets (one per org namespace gha-<org>).
#
# Usage:
#   export KUBECONFIG=$HOME/.kube/config-homelab
#   LAUNCHPAD_ENV=../.env ./scripts/k8s-github-actions-secret.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/scripts/lib/load-env.sh" ]]; then
  # shellcheck source=lib/load-env.sh
  source "$ROOT/scripts/lib/load-env.sh" "$ROOT"
fi

kubectl apply -f "$ROOT/k8s/github-actions/namespace.yaml"

upsert_secret() {
  local ns="$1" name="$2" token="$3"
  if [[ -z "$token" ]]; then
    echo "WARN: empty token for $ns/$name — skip" >&2
    return 0
  fi
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n "$ns" create secret generic "$name" \
    --from-literal=github_token="$token" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "secret/$name updated in namespace $ns"
}

if [[ -n "${GITHUB_ACTIONS_RUNNER_TOKEN:-}" && -n "${GITHUB_ACTIONS_RUNNER_ORG:-}" ]]; then
  case "$GITHUB_ACTIONS_RUNNER_ORG" in
    cap-jmk-launchpad) upsert_secret gha-cap-jmk-launchpad cap-jmk-launchpad-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    majico-xyz) upsert_secret gha-majico-xyz majico-xyz-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    librebase-official) upsert_secret gha-librebase-official librebase-official-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    obsevia-compliance) upsert_secret gha-obsevia-compliance obsevia-compliance-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    sailblack) upsert_secret gha-sailblack sailblack-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    taktwerk) upsert_secret gha-taktwerk taktwerk-arc "$GITHUB_ACTIONS_RUNNER_TOKEN" ;;
    *)
      echo "ERROR: unknown GITHUB_ACTIONS_RUNNER_ORG=$GITHUB_ACTIONS_RUNNER_ORG" >&2
      exit 1
      ;;
  esac
  exit 0
fi

upsert_secret gha-cap-jmk-launchpad cap-jmk-launchpad-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_CAP_JMK_LAUNCHPAD:-${GITHUB_ACTIONS_RUNNER_TOKEN_LAUNCHPAD:-${GH_TOKEN:-}}}"
upsert_secret gha-majico-xyz majico-xyz-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_MAJICO:-${GH_TOKEN:-}}"
upsert_secret gha-librebase-official librebase-official-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_LIBREBASE:-${GH_TOKEN:-}}"
upsert_secret gha-obsevia-compliance obsevia-compliance-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_OBSEVIA:-${GH_TOKEN:-}}"
upsert_secret gha-sailblack sailblack-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_SAILBLACK:-${GH_TOKEN:-}}"
upsert_secret gha-taktwerk taktwerk-arc "${GITHUB_ACTIONS_RUNNER_TOKEN_TAKTWERK:-}"
