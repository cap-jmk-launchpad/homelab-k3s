#!/usr/bin/env bash
# 10x GitLab CSS acceptance probe â€” sign_in + CSS size (default 835437).
set -euo pipefail

HOST="${EDGE_PROBE_HOST:-gitlab.lilangverse.xyz}"
RESOLVE="${EDGE_PROBE_RESOLVE:-}"
EXPECTED="${EDGE_PROBE_CSS_BYTES:-835437}"
RUNS="${EDGE_PROBE_RUNS:-10}"
SLEEP="${EDGE_PROBE_SLEEP:-3}"
TIMEOUT="${EDGE_PROBE_TIMEOUT:-120}"

CSS="${EDGE_PROBE_CSS:-}"
if [[ -z "$CSS" ]]; then
  local_args=( -sk --max-time "$TIMEOUT" )
  [[ -n "$RESOLVE" ]] && local_args+=( --resolve "$RESOLVE" )
  CSS=$(curl "${local_args[@]}" "https://${HOST}/users/sign_in" \
    | grep -oE '/assets/application-[a-f0-9]+\.css' | head -1)
fi
[[ -n "$CSS" ]] || { echo "FAIL: could not discover CSS path"; exit 1; }

label="${EDGE_PROBE_LABEL:-probe}"
pass=0
for i in $(seq 1 "$RUNS"); do
  args=( -sk -o /dev/null --max-time "$TIMEOUT" )
  [[ -n "$RESOLVE" ]] && args+=( --resolve "$RESOLVE" )
  sign=$(curl "${args[@]}" -w '%{http_code}' "https://${HOST}/users/sign_in" 2>/dev/null || echo 000)
  size=$(curl "${args[@]}" -w '%{size_download}' "https://${HOST}${CSS}" 2>/dev/null || echo 0)
  if { [[ "$sign" == "200" || "$sign" == "302" ]]; } && [[ "$size" == "$EXPECTED" ]]; then
    pass=$((pass + 1))
    echo "${label} run ${i}: PASS sign=${sign} css=${size}"
  else
    echo "${label} run ${i}: FAIL sign=${sign} css=${size}"
  fi
  sleep "$SLEEP"
done
echo "RESULT ${label}: ${pass}/${RUNS} pass (css=${CSS})"
[[ "$pass" -eq "$RUNS" ]]
