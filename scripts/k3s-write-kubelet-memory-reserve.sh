#!/usr/bin/env bash
# Reserve host memory so kubelet does not schedule pods into the OS safety margin.
# Usage: sudo SYSTEM_RESERVED_MEMORY=5Gi ./k3s-write-kubelet-memory-reserve.sh
set -euo pipefail

SYSTEM_RESERVED_MEMORY="${SYSTEM_RESERVED_MEMORY:-5Gi}"
KUBE_RESERVED_MEMORY="${KUBE_RESERVED_MEMORY:-512Mi}"
EVICTION_HARD="${EVICTION_HARD:-memory.available<1Gi}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo SYSTEM_RESERVED_MEMORY=$SYSTEM_RESERVED_MEMORY $0" >&2
  exit 1
fi

CFG_DIR="${HOST_ROOT:-}/etc/rancher/k3s"
CFG_FILE="$CFG_DIR/config.yaml"
mkdir -p "$CFG_DIR"

if [[ -f "$CFG_FILE" ]]; then
  cp -a "$CFG_FILE" "${CFG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
fi

python3 - "$CFG_FILE" "$SYSTEM_RESERVED_MEMORY" "$KUBE_RESERVED_MEMORY" "$EVICTION_HARD" <<'PY'
import sys
from pathlib import Path

cfg_path = Path(sys.argv[1])
sys_mem = sys.argv[2]
kube_mem = sys.argv[3]
eviction = sys.argv[4]

wanted = [
    f"system-reserved=memory={sys_mem}",
    f"kube-reserved=memory={kube_mem}",
    f"eviction-hard={eviction}",
]

text = cfg_path.read_text() if cfg_path.exists() else ""
lines = text.splitlines()
out: list[str] = []
i = 0
kubelet_block = False
existing: set[str] = set()

while i < len(lines):
    line = lines[i]
    if line.startswith("kubelet-arg:"):
        kubelet_block = True
        out.append(line)
        i += 1
        while i < len(lines) and lines[i].startswith("  - "):
            val = lines[i].split('"')[1] if '"' in lines[i] else lines[i]
            key = val.split("=")[0]
            existing.add(key)
            out.append(lines[i])
            i += 1
        for arg in wanted:
            key = arg.split("=")[0]
            if key not in existing:
                out.append(f'  - "{arg}"')
        kubelet_block = False
        continue
    out.append(line)
    i += 1

if not any(line.startswith("kubelet-arg:") for line in out):
    out.append("kubelet-arg:")
    for arg in wanted:
        out.append(f'  - "{arg}"')

cfg_path.write_text("\n".join(out).rstrip() + "\n")
PY

echo "Wrote memory reserve to $CFG_FILE:"
grep -E 'system-reserved|kube-reserved|eviction-hard' "$CFG_FILE" || true

if ${HOST_ROOT:+false} true; then
  if systemctl is-active --quiet k3s-agent; then
    systemctl restart k3s-agent
    echo "restarted k3s-agent"
  elif systemctl is-active --quiet k3s; then
    systemctl restart k3s
    echo "restarted k3s server"
  fi
else
  nsenter -t 1 -m -u -i -n -p -- systemctl restart k3s-agent || \
    nsenter -t 1 -m -u -i -n -p -- systemctl restart k3s || true
  echo "restarted k3s via nsenter"
fi
