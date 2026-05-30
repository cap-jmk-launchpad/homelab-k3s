#!/usr/bin/env bash
# Summarize Prometheus target health and sample PromQL (run on blackpearl).
set -euo pipefail
PROM_URL="${PROM_URL:-http://10.42.1.22:9090}"

curl -sf "${PROM_URL}/api/v1/targets" -o /tmp/prom-targets.json
python3 <<'PY'
import json
with open("/tmp/prom-targets.json") as f:
    d = json.load(f)
t = d["data"]["activeTargets"]
up = sum(1 for x in t if x["health"] == "up")
dn = [x for x in t if x["health"] != "up"]
print(f"UP={up} DOWN={len(dn)} TOTAL={len(t)}")
for x in dn[:15]:
    job = x["labels"].get("job", "?")
    err = (x.get("lastError") or "")[:100]
    print(f"  DOWN {job}: {err}")
PY

for q in up 'count(node_memory_MemTotal_bytes)' 'count(DCGM_FI_DEV_GPU_UTIL)'; do
  echo "=== $q ==="
  curl -sf "${PROM_URL}/api/v1/query?query=${q}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
r = d['data']['result']
print('series', len(r))
for x in r[:8]:
    m = x.get('metric', {})
    label = m.get('instance') or m.get('node') or m.get('job') or ''
    print(' ', label, x['value'][1])
"
done
