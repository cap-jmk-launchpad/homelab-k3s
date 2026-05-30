#!/usr/bin/env bash
# Fix Grafana configmap after bad min_interval values (run on blackpearl).
set -euo pipefail
CM=prometheus-stack-grafana
NS=monitoring
kubectl get cm -n "$NS" "$CM" -o json |
  python3 -c '
import json, sys
cm = json.load(sys.stdin)
ini = cm["data"]["grafana.ini"]
out = []
skip = False
for line in ini.splitlines():
    if line.strip() == "[unified_alerting]":
        skip = True
        continue
    if skip:
        if line.startswith("["):
            skip = False
        else:
            continue
    if line.startswith("min_refresh_interval"):
        continue
    out.append(line)
cm["data"]["grafana.ini"] = "\n".join(out) + "\n"
json.dump(cm, sys.stdout)
' | kubectl apply -f -
kubectl rollout restart deployment/prometheus-stack-grafana -n "$NS"
kubectl rollout status deployment/prometheus-stack-grafana -n "$NS" --timeout=4m
kubectl get cm -n "$NS" "$CM" -o yaml | grep -A6 '\[dashboards\]'
