#!/usr/bin/env bash
# Write /etc/rancher/k3s/config.yaml kubelet max-pods (merge if file exists).
# Usage: sudo MAX_PODS=250 ./k3s-write-kubelet-max-pods.sh
set -euo pipefail

MAX_PODS="${MAX_PODS:?Set MAX_PODS e.g. 250}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo MAX_PODS=$MAX_PODS $0" >&2
  exit 1
fi

CFG_DIR=/etc/rancher/k3s
CFG_FILE="$CFG_DIR/config.yaml"
mkdir -p "$CFG_DIR"

if [[ -f "$CFG_FILE" ]] && grep -q 'max-pods' "$CFG_FILE"; then
  echo "kubelet max-pods already present in $CFG_FILE"
  exit 0
fi

if [[ -f "$CFG_FILE" ]]; then
  cp -a "$CFG_FILE" "${CFG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  if grep -q '^kubelet-arg:' "$CFG_FILE"; then
    sed -i "/^kubelet-arg:/a\\  - \"max-pods=${MAX_PODS}\"" "$CFG_FILE"
  else
    printf '\n%s\n' 'kubelet-arg:' "  - \"max-pods=${MAX_PODS}\"" >> "$CFG_FILE"
  fi
else
  cat > "$CFG_FILE" <<EOF
kubelet-arg:
  - "max-pods=${MAX_PODS}"
EOF
fi

echo "Wrote max-pods=${MAX_PODS} to $CFG_FILE"