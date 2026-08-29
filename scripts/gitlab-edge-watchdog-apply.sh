#!/usr/bin/env bash
# DEPRECATED — superseded by scripts/deploy-cluster-watchdog.sh (single cluster-watchdog
# timer). This wrapper still drops gitlab-edge-watchdog.sh into /usr/local/bin (it is now
# only an internal healer invoked by cluster-watchdog.sh heall_edge), but it no longer
# arms the retired gitlab-edge-watchdog.timer. Use the unified deploy instead:
#   sudo bash scripts/deploy-cluster-watchdog.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

[[ "$(id -u)" -eq 0 ]] || { echo "run as root on blackpearl" >&2; exit 1; }

install -d /usr/local/bin
install -m 755 "${SCRIPT_DIR}/gitlab-edge-watchdog.sh" /usr/local/bin/gitlab-edge-watchdog.sh

echo "gitlab-edge-watchdog-apply: gitlab-edge-watchdog.sh installed (timer retired)."
echo "gitlab-edge-watchdog-apply: arming the unified cluster-watchdog instead:"
bash "${SCRIPT_DIR}/deploy-cluster-watchdog.sh"
