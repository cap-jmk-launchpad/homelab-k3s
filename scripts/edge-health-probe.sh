#!/usr/bin/env bash
# Post-start probe for li-httpd edge units (ExecStartPost).
# Always hits local li-httpd via --resolve (never the public WAN IP — avoids NAT hairpin).
set -euo pipefail

PORT="${1:-80}"
HOST="${2:-gitlab.lilangverse.xyz}"
PATH_PROBE="${3:-/health}"
LOCAL_BIND="${EDGE_HEALTH_LOCAL_BIND:-127.0.0.1}"
TIMEOUT="${EDGE_HEALTH_TIMEOUT:-15}"

if command -v curl >/dev/null 2>&1; then
  if [[ "$PORT" == "443" ]]; then
    curl -fsS --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" \
      -k --resolve "${HOST}:${PORT}:${LOCAL_BIND}" \
      "https://${HOST}${PATH_PROBE}" >/dev/null
  else
    curl -fsS --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" \
      --resolve "${HOST}:${PORT}:${LOCAL_BIND}" \
      "http://${HOST}${PATH_PROBE}" >/dev/null
  fi
elif command -v wget >/dev/null 2>&1; then
  if [[ "$PORT" == "443" ]]; then
    wget -qO- --timeout="$TIMEOUT" --no-check-certificate \
      --header="Host: ${HOST}" "https://${LOCAL_BIND}${PATH_PROBE}" >/dev/null
  else
    wget -qO- --timeout="$TIMEOUT" --header="Host: ${HOST}" \
      "http://${LOCAL_BIND}${PATH_PROBE}" >/dev/null
  fi
else
  echo "edge-health-probe: need curl or wget" >&2
  exit 1
fi

echo "edge-health-probe: OK ${HOST}:${PORT}${PATH_PROBE} (via ${LOCAL_BIND})"