#!/usr/bin/env bash
# Enable homelab ARC runners for all repos in each org (org-level Actions variables).
# Workflows opt in with runs-on: home-k3s (or product-specific labels on the same runners).
#
set -euo pipefail

set_org_var() {
  local org="$1" name="$2" value="$3"
  if gh variable set "$name" --org "$org" --body "$value" 2>/dev/null; then
    echo "OK $org $name=$value"
  else
    echo "WARN: could not set $org $name (need org admin)" >&2
  fi
}

set_org_var cap-jmk-launchpad HOMELAB_RUNNER_ENABLED true
set_org_var majico-xyz MAJICO_SELF_HOSTED_RUNNER true
set_org_var majico-xyz HOMELAB_RUNNER_ENABLED true
set_org_var librebase-official LIBREBASE_SELF_HOSTED_RUNNER true
set_org_var librebase-official HOMELAB_RUNNER_ENABLED true
set_org_var obsevia-compliance HOMELAB_K8S_HEALTH_ENABLED true
set_org_var obsevia-compliance HOMELAB_RUNNER_ENABLED true
set_org_var sailblack HOMELAB_RUNNER_ENABLED true

echo "Done. Any workflow job with runs-on: home-k3s can use homelab runners in that org."
