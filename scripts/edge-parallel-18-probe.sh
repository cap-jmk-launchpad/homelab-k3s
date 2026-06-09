#!/usr/bin/env bash
# Parallel 18-asset GitLab sign_in probe (browser load pattern).
# Pass: every asset HTTP 200, wc -c == Content-Length, body not HTML error.
set -euo pipefail

HOST="${EDGE_PROBE_HOST:-gitlab.lilangverse.xyz}"
RESOLVE="${EDGE_PROBE_RESOLVE:?EDGE_PROBE_RESOLVE required, e.g. gitlab.lilangverse.xyz:443:127.0.0.1}"
LABEL="${EDGE_PROBE_LABEL:-parallel-18}"
HTML="/tmp/edge_parallel_sign_in.html"
ASSETS="/tmp/edge_parallel_assets18.txt"

curl -sk --http1.1 --no-keepalive --resolve "$RESOLVE" -o "$HTML" --max-time 30 "https://${HOST}/users/sign_in" \
  || { test -s "$HTML" || exit 1; }
grep -oE '(href|src)="(/assets/[^"]+\.(css|js))"' "$HTML" \
  | sed -E 's/.*="([^"]+)".*/\1/' | sort -u > "$ASSETS"
n=$(wc -l < "$ASSETS")
[[ "$n" -eq 18 ]] || { echo "FAIL ${LABEL}: expected 18 assets, got ${n}"; exit 1; }

tmpdir=$(mktemp -d)
results="${tmpdir}/results.txt"
: > "$results"
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
    echo "${code} ${wire} ${clen} ${first} ${path}" > "$res"
  ) &
  pids="${pids} $!"
done < "$ASSETS"
for pid in $pids; do wait "$pid" || true; done
cat "${tmpdir}"/*.result > "$results" 2>/dev/null || true

pass=0
fail=0
while read -r code wire clen first path; do
  if [[ "$code" == "200" && -n "$clen" && "$wire" == "$clen" && "$first" != "3c" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL ${code} wire=${wire} clen=${clen} first=${first} ${path}"
  fi
done < "$results"
echo "RESULT ${LABEL}: ${pass}/${n}"
rm -rf "$tmpdir"
[[ "$fail" -eq 0 ]]
