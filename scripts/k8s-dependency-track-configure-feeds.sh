#!/usr/bin/env bash
# Apply aggressive vulnerability mirror cadence via REST API (requires DEPTRACK_API_KEY).
# Mirror intervals are stored in HOURS (integer) — minimum 1h; 10-minute cadence is not supported upstream.
#
# Usage:
#   LAUNCHPAD_ENV=../.env ./scripts/k8s-dependency-track-configure-feeds.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHPAD_ENV="${LAUNCHPAD_ENV:-$(dirname "$ROOT")/.env}"

# shellcheck source=lib/load-launchpad-deptrack-env.sh
source "$ROOT/scripts/lib/load-launchpad-deptrack-env.sh"
load_launchpad_deptrack_env

DEPTRACK_NAMESPACE="${DEPTRACK_NAMESPACE:-dependency-track}"
DEPTRACK_MIRROR_CADENCE_HOURS="${DEPTRACK_MIRROR_CADENCE_HOURS:-1}"
API_KEY="${DEPTRACK_API_KEY:-}"
API_BASE="${DEPTRACK_API_BASE_URL:-http://dependency-track-api-server.${DEPTRACK_NAMESPACE}.svc.cluster.local:8080}"
API_POD="$(kubectl -n "$DEPTRACK_NAMESPACE" get pods -l app.kubernetes.io/component=api-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "$API_POD" ]] || API_POD="dependency-track-api-server-0"

if [[ -z "$API_KEY" ]]; then
  echo "SKIP: DEPTRACK_API_KEY not set in $LAUNCHPAD_ENV"
  echo "      Create an API key (Administration → Access Management → Teams → Automation)"
  echo "      with SYSTEM_CONFIGURATION, add DEPTRACK_API_KEY=..., re-run this script."
  exit 0
fi

cadence="$DEPTRACK_MIRROR_CADENCE_HOURS"
if [[ "$cadence" -lt 1 ]]; then
  echo "WARN: DEPTRACK_MIRROR_CADENCE_HOURS=$cadence — using minimum 1 (hours)" >&2
  cadence=1
fi

payload="$(cat <<EOF
[
  {"groupName":"task-scheduler","propertyName":"nist.mirror.cadence","propertyValue":"${cadence}"},
  {"groupName":"task-scheduler","propertyName":"ghsa.mirror.cadence","propertyValue":"${cadence}"},
  {"groupName":"task-scheduler","propertyName":"osv.mirror.cadence","propertyValue":"${cadence}"},
  {"groupName":"task-scheduler","propertyName":"vulndb.mirror.cadence","propertyValue":"${cadence}"},
  {"groupName":"task-scheduler","propertyName":"portfolio.vulnerability.analysis.cadence","propertyValue":"${cadence}"},
  {"groupName":"vuln-source","propertyName":"github.advisories.enabled","propertyValue":"true"}
]
EOF
)"

echo "==> set mirror cadence to ${cadence}h (requested 10min not supported — see docs)"
if kubectl -n "$DEPTRACK_NAMESPACE" get pod "$API_POD" >/dev/null 2>&1; then
  kubectl -n "$DEPTRACK_NAMESPACE" exec "$API_POD" -- \
    curl -fsS -X POST \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: ${API_KEY}" \
    "http://127.0.0.1:8080/api/v1/configProperty/aggregate" \
    --data "${payload}" >/dev/null
else
  curl -fsS -X POST \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: ${API_KEY}" \
    "${API_BASE}/api/v1/configProperty/aggregate" \
    --data "${payload}" >/dev/null
fi

echo "==> restart apiserver so task scheduler picks up new cadence"
kubectl -n "$DEPTRACK_NAMESPACE" rollout restart statefulset/dependency-track-api-server
kubectl -n "$DEPTRACK_NAMESPACE" rollout status statefulset/dependency-track-api-server --timeout=900s

echo "==> done (initial NVD/GHSA/OSV mirror may still take 10–30+ minutes on first boot)"
