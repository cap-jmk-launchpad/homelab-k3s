#!/usr/bin/env bash
# Strict edge acceptance gate — TESTED or NOT TESTED only (no partial success).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="${EDGE_PROBE_HOST:-gitlab.lilangverse.xyz}"

echo "=== edge acceptance gate (blackpearl) ==="

echo "--- parallel edge 127.0.0.1 ---"
EDGE_PROBE_RESOLVE="${HOST}:443:127.0.0.1" EDGE_PROBE_LABEL=parallel-127 \
  bash "${SCRIPT_DIR}/edge-parallel-18-probe.sh"

echo "--- parallel edge 192.168.10.33 ---"
EDGE_PROBE_RESOLVE="${HOST}:443:192.168.10.33" EDGE_PROBE_LABEL=parallel-33 \
  bash "${SCRIPT_DIR}/edge-parallel-18-probe.sh"

echo "--- sequential 18 assets (127.0.0.1) ---"
RESOLVE="${HOST}:443:127.0.0.1"
HTML=/tmp/edge_seq_sign_in.html
curl -sk --http1.1 --resolve "$RESOLVE" -o "$HTML" --max-time 30 "https://${HOST}/users/sign_in"
grep -oE '(href|src)="(/assets/[^"]+\.(css|js))"' "$HTML" \
  | sed -E 's/.*="([^"]+)".*/\1/' | sort -u > /tmp/edge_seq_assets18.txt
seq_pass=0
while IFS= read -r path; do
  meta=$(curl -sk --http1.1 --resolve "$RESOLVE" -D /tmp/edge_seq.hdr -o /tmp/edge_seq.body \
    -w '%{http_code} %{size_download}' --max-time 180 "https://${HOST}${path}")
  code=$(echo "$meta" | awk '{print $1}')
  dl=$(echo "$meta" | awk '{print $2}')
  clen=$(grep -i '^content-length:' /tmp/edge_seq.hdr | tail -1 | awk '{print $2}' | tr -d '\r')
  first=$(head -c 1 /tmp/edge_seq.body | od -An -tx1 | tr -d ' \n')
  if [[ "$code" == "200" && "$dl" == "$clen" && "$first" != "3c" ]]; then
    seq_pass=$((seq_pass + 1))
  else
    echo "FAIL seq ${code} dl=${dl} clen=${clen} ${path}"
  fi
done < /tmp/edge_seq_assets18.txt
echo "RESULT sequential-127: ${seq_pass}/18"
[[ "$seq_pass" -eq 18 ]]

echo "--- edge-css-probe 10/10 loopback ---"
EDGE_PROBE_RESOLVE="${HOST}:443:127.0.0.1" EDGE_PROBE_LABEL=css-loopback \
  bash "${SCRIPT_DIR}/edge-css-probe.sh"

echo "--- edge-css-probe 10/10 LAN resolve ---"
EDGE_PROBE_RESOLVE="${HOST}:443:192.168.10.33" EDGE_PROBE_LABEL=css-lan \
  bash "${SCRIPT_DIR}/edge-css-probe.sh"

echo "STATUS: TESTED"
