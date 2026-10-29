#!/usr/bin/env bash
# Updates agentic-book.org DNS records on IONOS to the current WAN IP.
set -euo pipefail

WAN_IP="$(curl -s --max-time 10 https://ifconfig.me || curl -s --max-time 10 https://api.ipify.org)"
if [[ -z "$WAN_IP" ]]; then
  echo "Error: could not determine WAN IP" >&2
  exit 1
fi

if [[ -z "${IONOS_API_PREFIX:-}" ]] || [[ -z "${IONOS_API_SECRET:-}" ]]; then
  if [[ -f "$HOME/Documents/coding-projects/.env" ]]; then
    # Load credentials from .env if present
    IONOS_API_PREFIX="$(grep '^IONOS_API_PREFIX=' "$HOME/Documents/coding-projects/.env" | cut -d'=' -f2- | tr -d '"'\''')"
    IONOS_API_SECRET="$(grep '^IONOS_API_SECRET=' "$HOME/Documents/coding-projects/.env" | cut -d'=' -f2- | tr -d '"'\''')"
  fi
fi

if [[ -z "${IONOS_API_PREFIX:-}" ]] || [[ -z "${IONOS_API_SECRET:-}" ]]; then
  echo "Error: IONOS_API_PREFIX and IONOS_API_SECRET must be set in environment or in .env" >&2
  exit 1
fi
ZONE_ID="${IONOS_ZONE_ID:-4cdc331a-95d8-11f1-9400-0a5864441388}"
API_KEY="${IONOS_API_PREFIX}.${IONOS_API_SECRET}"

RECORDS=(
  "agentic-book.org:dcfa4c63-e85d-cc0e-d52a-a43c992d94fc"
  "www.agentic-book.org:6180581e-4a5e-3b0a-03f2-a7f858d5501e"
  "supabase.agentic-book.org:b0c59485-180d-2789-0826-b3ea7d41724c"
  "mcp.agentic-book.org:662c227d-d02c-02ee-2497-3fbc3706981a"
  "shiphook.agentic-book.org:889561ff-4e59-aa50-ecff-1e6057306fff"
)

echo "Updating agentic-book.org records to WAN IP: ${WAN_IP}"
for item in "${RECORDS[@]}"; do
  NAME="${item%%:*}"
  REC_ID="${item##*:}"
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    "https://api.hosting.ionos.com/dns/v1/zones/${ZONE_ID}/records/${REC_ID}" \
    -H "X-API-Key: ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"${WAN_IP}\",\"ttl\":300,\"disabled\":false}")
  echo "  ${NAME} -> ${WAN_IP} (HTTP ${STATUS})"
done
