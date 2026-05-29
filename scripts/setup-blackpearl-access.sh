#!/usr/bin/env bash
# Wrapper — see apply-server-prep.sh for full implementation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${SCRIPT_DIR}/apply-server-prep.sh" "$@"
