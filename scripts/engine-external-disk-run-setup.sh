#!/usr/bin/env bash
set -euo pipefail
REPO="${REPO:-$HOME/beelink-cleanup}"
python3 <<'PY'
from pathlib import Path
src = Path(__import__("os").environ["REPO"]) / "scripts/engine-external-disk-setup.sh"
dst = Path("/tmp/engine-external-disk-setup.sh")
data = src.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"")
dst.write_bytes(data)
print(f"Wrote {dst} ({len(data)} bytes)")
PY
sed 's/\r$//' /tmp/engine-external-disk-setup.sh | kubectl exec -i -n kube-system engine-disk-setup -c setup -- nsenter -t 1 -m -u -i -n -p bash -s
