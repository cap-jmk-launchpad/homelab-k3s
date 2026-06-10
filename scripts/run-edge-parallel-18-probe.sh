#!/usr/bin/env bash
# Wrapper with workstation defaults — avoids inline env assignment (Windows npm).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export EDGE_PROBE_RESOLVE="${EDGE_PROBE_RESOLVE:-gitlab.lilangverse.xyz:443:192.168.10.33}"
export EDGE_PROBE_LABEL="${EDGE_PROBE_LABEL:-parallel-edge}"
exec bash "${SCRIPT_DIR}/edge-parallel-18-probe.sh"
