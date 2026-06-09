#!/usr/bin/env bash
# Sequential 18-asset curl probe (accurate field parsing).
set -eu

HOST="${GITLAB_HOST:-gitlab.lilangverse.xyz}"
EDGE_IP="${EDGE_IP:-192.168.10.33}"
RESOLVE="${HOST}:443:${EDGE_IP}"
HTML="${TMPDIR:-/tmp}/gitlab_sign_in.html"
ASSET_LIST="${TMPDIR:-/tmp}/gitlab_assets18.txt"

curl -sk --http1.1 --no-keepalive --resolve "$RESOLVE" -o "$HTML" --max-time 60 \
  "https://${HOST}/users/sign_in"

grep -oE '(href|src)="(/assets/[^"]+\.(css|js))"' "$HTML" \
  | sed -E 's/.*="([^"]+)".*/\1/' | sort -u > "$ASSET_LIST"

n=$(wc -l < "$ASSET_LIST" | tr -d ' ')
echo "assets=${n}"

pass=0
while IFS= read -r path; do
  out="${TMPDIR:-/tmp}/probe.body"
  hdr="${TMPDIR:-/tmp}/probe.hdr"
  meta=$(curl -sk --http1.1 --no-keepalive --resolve "$RESOLVE" -D "$hdr" -o "$out" \
    -w '%{http_code} %{size_download}' --max-time 180 "https://${HOST}${path}" 2>/dev/null || echo '000 0')
  code=$(echo "$meta" | awk '{print $1}')
  dl=$(echo "$meta" | awk '{print $2}')
  clen=$(grep -i '^content-length:' "$hdr" 2>/dev/null | tail -1 | awk '{print $2}' | tr -d '\r')
  first=$(head -c 1 "$out" 2>/dev/null | od -An -tx1 | tr -d ' \n' || echo x)
  if [ "$code" = "200" ] && [ -n "$clen" ] && [ "$dl" = "$clen" ] && [ "$first" != "3c" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL ${code} dl=${dl} clen=${clen:-?} first=${first:-?} ${path}"
  fi
done < "$ASSET_LIST"

echo "RESULT sequential-edge: ${pass}/${n}"
[ "$pass" -eq "$n" ] && [ "$n" -ge 1 ]
