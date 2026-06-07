#!/usr/bin/env bash
# Validate homelab + majico li-httpd TOML (lis oracle). Run locally or on blackpearl.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EDGE_DIR="${REPO_ROOT}/k8s/edge"

bash "${SCRIPT_DIR}/homelab-edge-policy-check.sh"

LIS_ROOT="${LIS_ROOT:-}"
LIC_ROOT="${LIC_ROOT:-${HOME}/staging/lic}"
if [[ -z "$LIS_ROOT" ]]; then
  for candidate in \
    "${HOME}/staging/lis" \
    "${REPO_ROOT}/../li/lis" \
    "/home/s4il0r/staging/lis"; do
    if [[ -f "${candidate}/scripts/httpd_config.py" ]]; then
      LIS_ROOT="$candidate"
      break
    fi
  done
fi
export LIS_ROOT LIC_ROOT

MAJICO_HTTPD_TOML="${MAJICO_HTTPD_TOML:-/home/s4il0r/staging/majico.xyz/deploy/staging/edge/majico-staging.httpd.toml}"
MERGED="/tmp/homelab-edge.merged.toml"

inputs=("${EDGE_DIR}/homelab.httpd.toml")
if [[ -f "$MAJICO_HTTPD_TOML" ]]; then
  inputs+=("$MAJICO_HTTPD_TOML")
else
  echo "note: majico TOML missing ($MAJICO_HTTPD_TOML) — homelab routes only" >&2
fi

export LIS_ROOT LIC_ROOT
python3 "${EDGE_DIR}/merge-httpd-config.py" "${inputs[@]}" -o "$MERGED" --validate

validate_root=""
if [[ -n "$LIS_ROOT" && -f "${LIS_ROOT}/scripts/httpd_config.py" ]]; then
  validate_root="${LIS_ROOT}/scripts"
elif [[ -f "${LIC_ROOT}/scripts/httpd_config.py" ]]; then
  validate_root="${LIC_ROOT}/scripts"
fi
[[ -n "$validate_root" ]] || { echo "LIS_ROOT/LIC_ROOT not found for validate" >&2; exit 1; }
export PYTHONPATH="${validate_root}${PYTHONPATH:+:$PYTHONPATH}"
python3 - <<PY
from pathlib import Path
from httpd_config import load_httpd_sites
sites = load_httpd_sites(Path("${MERGED}"))
print(f"lis http validate: OK ({len(sites)} sites)")
PY
echo "edge-lis-validate: OK"
