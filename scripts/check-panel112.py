#!/usr/bin/env python3
import base64
import json
import os
import sys
import urllib.request

GRAF_URL = os.environ.get("GRAF_URL", "http://127.0.0.1:30300").rstrip("/")
USER = os.environ.get("GRAFANA_USER", "admin")
PW = os.environ.get("GRAFANA_PW", "HomelabGraf2026!")


def panel112_overrides(uid: str) -> int:
    creds = base64.b64encode(f"{USER}:{PW}".encode()).decode()
    req = urllib.request.Request(
        f"{GRAF_URL}/api/dashboards/uid/{uid}",
        headers={"Authorization": f"Basic {creds}"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.load(resp)
    panel = next(p for p in body["dashboard"]["panels"] if p.get("id") == 112)
    return len(panel["fieldConfig"].get("overrides") or [])


def main() -> int:
    uids = sys.argv[1:] or ["homelab-cluster-resources", "homelab-cluster-resources-live"]
    ok = True
    for uid in uids:
        try:
            n = panel112_overrides(uid)
        except Exception as exc:
            print(f"{uid}: ERROR {exc}")
            ok = False
            continue
        print(f"{uid}: panel112_overrides={n}")
        if n < 5:
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
