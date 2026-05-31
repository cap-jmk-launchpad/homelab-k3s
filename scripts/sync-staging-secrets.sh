#!/usr/bin/env bash
# Sync local majico .env.staging to blackpearl (never commit secrets).
# Usage (from Git Bash or WSL on PC):
#   STAGING_HOST=192.168.10.41 \
#   STAGING_KEY=../blackpearl \
#   ENV_FILE=../../branding_saas_projects/deploy/staging/.env.staging \
#   bash sync-staging-secrets.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh" "$ROOT"

STAGING_USER="${STAGING_USER:-s4il0r}"
STAGING_HOST="${STAGING_HOST:-blackpearl}"
STAGING_KEY="${STAGING_KEY:-$(dirname "$0")/../blackpearl}"
ENV_FILE="${ENV_FILE:-}"

if [[ -z "$ENV_FILE" || ! -f "$ENV_FILE" ]]; then
  echo "Set ENV_FILE to local .env.staging path" >&2
  exit 1
fi

SSH=(ssh -i "$STAGING_KEY" -o IdentitiesOnly=yes "${STAGING_USER}@${STAGING_HOST}")
SCP=(scp -i "$STAGING_KEY" -o IdentitiesOnly=yes)

"${SSH[@]}" "mkdir -p ~/staging/secrets && chmod 700 ~/staging/secrets"
"${SCP[@]}" "$ENV_FILE" "${STAGING_USER}@${STAGING_HOST}:staging/secrets/.env.staging"
"${SSH[@]}" "chmod 600 ~/staging/secrets/.env.staging"
echo "Synced secrets to ~/staging/secrets/.env.staging on ${STAGING_HOST}"