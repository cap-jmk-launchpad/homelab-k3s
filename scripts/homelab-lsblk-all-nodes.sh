#!/usr/bin/env bash
set -euo pipefail
nodes=(anch0r:22 deck:26 desktop:31 engine:32 blackpearl:33)
for entry in "${nodes[@]}"; do
  name="${entry%%:*}"
  ip="${entry##*:}"
  echo "=== ${name} (192.168.10.${ip}) ==="
  port=22
  if [[ "$name" == "desktop" ]]; then port=2222; fi
  ssh -o BatchMode=yes -o ConnectTimeout=8 -p "$port" "s4il0r@192.168.10.${ip}" \
    'lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS; echo; df -hT -x tmpfs -x devtmpfs | head -20' 2>&1 || echo "(ssh failed)"
  echo
done
