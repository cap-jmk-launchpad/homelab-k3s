#!/usr/bin/env bash
# Reserve host memory so k3s cannot schedule pods into the last N GiB (OOM safety).
# Usage (on engine): sudo SYSTEM_RESERVED_MEMORY=5Gi ./k3s-write-kubelet-memory-reserve.sh
# Optional: KUBE_RESERVED_MEMORY=512Mi EVICTION_MEMORY=1Gi
set -euo pipefail

SYSTEM_RESERVED_MEMORY="${SYSTEM_RESERVED_MEMORY:-5Gi}"
KUBE_RESERVED_MEMORY="${KUBE_RESERVED_MEMORY:-512Mi}"
EVICTION_MEMORY="${EVICTION_MEMORY:-1Gi}"
RESTART_K3S="${RESTART_K3S:-1}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo SYSTEM_RESERVED_MEMORY=${SYSTEM_RESERVED_MEMORY} $0" >&2
  exit 1
fi

CFG_DIR=/etc/rancher/k3s
CFG_FILE="${CFG_DIR}/config.yaml"
mkdir -p "$CFG_DIR"

[[ -f "$CFG_FILE" ]] && cp -a "$CFG_FILE" "${CFG_FILE}.bak.$(date +%Y%m%d%H%M%S)"

python3 - "$CFG_FILE" "$SYSTEM_RESERVED_MEMORY" "$KUBE_RESERVED_MEMORY" "$EVICTION_MEMORY" <<'PY'
import sys
from pathlib import Path

cfg_path = Path(sys.argv[1])
sys_mem = sys.argv[2]
kube_mem = sys.argv[3]
evict = sys.argv[4]

want = {
    f"system-reserved=memory={sys_mem},cpu=250m",
    f"kube-reserved=memory={kube_mem},cpu=100m",
    f"eviction-hard=memory.available<{evict},imagefs.available<10%",
}

text = cfg_path.read_text() if cfg_path.exists() else ""
lines = text.splitlines()

def strip_arg(line: str) -> str | None:
    line = line.strip()
    if not line.startswith("- "):
        return None
    val = line[2:].strip().strip('"').strip("'")
    return val.split("=", 1)[0] if "=" in val else val

out: list[str] = []
in_kubelet = False
existing: list[str] = []

for line in lines:
    if line.startswith("kubelet-arg:"):
        in_kubelet = True
        out.append(line)
        continue
    if in_kubelet:
        if line.startswith("  - "):
            existing.append(line)
            continue
        in_kubelet = False
    out.append(line)

prefixes = {
    "system-reserved",
    "kube-reserved",
    "eviction-hard",
}
kept = []
for line in existing:
    val = strip_arg(line)
    if val and any(val.startswith(p) for p in prefixes):
        continue
    kept.append(line)

final_args = kept + [f'  - "{arg}"' for arg in sorted(want)]

if "kubelet-arg:" not in out:
    if out and out[-1].strip():
        out.append("")
    out.append("kubelet-arg:")
else:
    # replace block: find kubelet-arg line index and drop until non-indented
    idx = out.index("kubelet-arg:")
    out = out[: idx + 1]

out.extend(final_args)
cfg_path.write_text("\n".join(out).rstrip() + "\n")
print(f"Wrote kubelet memory reserve to {cfg_path}")
for arg in sorted(want):
    print(f"  {arg}")
PY

if [[ "$RESTART_K3S" == "1" ]]; then
  if systemctl is-active --quiet k3s-agent; then
    systemctl restart k3s-agent
    echo "restarted k3s-agent"
  elif systemctl is-active --quiet k3s; then
    systemctl restart k3s
    echo "restarted k3s server"
  fi
fi
