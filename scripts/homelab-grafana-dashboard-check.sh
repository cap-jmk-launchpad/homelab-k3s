#!/usr/bin/env bash
set -euo pipefail
curl -sf -u admin:HomelabGraf2026! \
  'http://127.0.0.1:30300/api/dashboards/uid/efa86fd1d0c121a26444b636a3f509a8' |
  python3 -c '
import json, sys
d = json.load(sys.stdin)
p = d["dashboard"]
print("title:", p["title"])
for v in p.get("templating", {}).get("list", []):
    print("var", v.get("name"), "current=", v.get("current"), "options=", len(v.get("options", [])))
for pan in p.get("panels", []):
    t = pan.get("title", "")
    if any(x in t for x in ("Memory", "CPU")):
        unit = pan.get("fieldConfig", {}).get("defaults", {}).get("unit")
        exprs = [x.get("expr", "")[:100] for x in pan.get("targets", [])]
        print("panel:", t, "unit=", unit, "exprs=", exprs)
'
