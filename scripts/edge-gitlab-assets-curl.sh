#!/usr/bin/env bash
# Parallel 18-asset curl probe for GitLab sign_in via edge (strict 18/18 gate).
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

tmpdir=$(mktemp -d)
results="${tmpdir}/results.txt"
: > "${results}"
pids=""

while IFS= read -r path; do
  (
    set +e
    safe=$(printf '%s' "$path" | md5sum | awk '{print $1}')
    out="${tmpdir}/${safe}.body"
    hdr="${tmpdir}/${safe}.hdr"
    res="${tmpdir}/${safe}.result"
    curl -sk --http1.1 --no-keepalive --resolve "$RESOLVE" -D "$hdr" -o "$out" \
      --max-time 180 "https://${HOST}${path}" 2>/dev/null
    code=$(grep -m1 'HTTP/' "$hdr" 2>/dev/null | awk '{print $2}')
    [[ -n "$code" ]] || code=000
    wire=0
    if [[ -f "$out" ]]; then
      wire=$(wc -c < "$out" | tr -d ' ')
    fi
    clen=$(grep -i '^content-length:' "$hdr" 2>/dev/null | tail -1 | awk '{print $2}' | tr -d '\r')
    first=$(head -c 1 "$out" 2>/dev/null | od -An -tx1 | tr -d ' \n' || echo x)
    echo "${code}|${wire}|${clen}|${first}|${path}" > "$res"
  ) &
  pids="${pids} $!"
done < "$ASSET_LIST"

for pid in $pids; do wait "$pid" || true; done
cat "${tmpdir}"/*.result > "${results}" 2>/dev/null || true

pass=0
fail=0
while IFS='|' read -r code wire clen first path; do
  if [ "$code" = "200" ] && [ -n "$clen" ] && [ "$wire" = "$clen" ] && [ "$first" != "3c" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL ${code} wire=${wire} clen=${clen} first=${first} ${path}"
  fi
done < "${results}"

echo "RESULT parallel-edge: ${pass}/${n}"
rm -rf "${tmpdir}"
[ "$pass" -eq "$n" ] && [ "$n" -ge 1 ]
