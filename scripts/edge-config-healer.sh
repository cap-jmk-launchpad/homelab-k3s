#!/usr/bin/env bash
# Deprecated wrapper — portfolio SNI healer now lives in homelab-edge-policy-check.sh
# Usage: bash scripts/edge-config-healer.sh [--check|--fix|--json]
# For live blackpearl checks (cert SAN, Host-header probe) run homelab-edge-policy-check.sh
# plus: openssl s_client -connect 127.0.0.1:443 -servername www.julianmkleber.com
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Forward all args; --fix is the only arg that changes behaviour (patches repo)
if [[ "${*:-}" == *"--fix"* ]]; then
  exec bash "${SCRIPT_DIR}/homelab-edge-policy-check.sh" --fix
else
  exec bash "${SCRIPT_DIR}/homelab-edge-policy-check.sh"
fi
