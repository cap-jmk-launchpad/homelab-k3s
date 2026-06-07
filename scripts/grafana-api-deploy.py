#!/usr/bin/env python3
"""Import homelab Grafana dashboards via HTTP API (no kubectl required)."""
from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
MON = REPO / "k8s/monitoring"
GRAF_URL = os.environ.get(
    "GRAF_URL",
    "http://127.0.0.1:30300" if Path("/etc/rancher/k3s/k3s.yaml").exists() else "http://192.168.10.41:30300",
).rstrip("/")
GRAFANA_USER = os.environ.get("GRAFANA_USER", "admin")
GRAFANA_PW = os.environ.get("GRAFANA_PW", "HomelabGraf2026!")

DASHBOARDS = (
    "homelab-cluster-resources-dashboard.json",
    "homelab-gpu-dashboard.json",
)

# Provisioned sidecar UIDs cannot be overwritten via API; import as -live copies.
LIVE_UID_SUFFIX = os.environ.get("GRAFANA_LIVE_SUFFIX", "-live")


def import_dashboard(path: Path) -> dict:
    dash = json.loads(path.read_text(encoding="utf-8"))
    if LIVE_UID_SUFFIX:
        dash["id"] = None
        dash["uid"] = f"{dash['uid']}{LIVE_UID_SUFFIX}"
        dash["title"] = f"{dash['title']} (live)"
    payload = json.dumps(
        {
            "dashboard": dash,
            "overwrite": True,
            "message": "grafana-api-deploy.py",
        }
    ).encode()
    creds = base64.b64encode(f"{GRAFANA_USER}:{GRAFANA_PW}".encode()).decode()
    req = urllib.request.Request(
        f"{GRAF_URL}/api/dashboards/db",
        data=payload,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Basic {creds}",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode())


def main() -> int:
    for name in DASHBOARDS:
        path = MON / name
        if not path.is_file():
            print(f"MISSING {path}", file=sys.stderr)
            return 1
        try:
            body = import_dashboard(path)
        except urllib.error.HTTPError as exc:
            print(f"FAIL {name}: HTTP {exc.code} {exc.read().decode()}", file=sys.stderr)
            return 1
        uid = body.get("uid") or json.loads(path.read_text())["uid"]
        print(f"OK {uid}: version={body.get('version')} url={GRAF_URL}{body.get('url', '')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
