#!/usr/bin/env bash
# Generate vault.klaut.pro static status + /healthz from Vault unseal + ClusterSecretStore readiness.
set -euo pipefail

ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STATIC_ROOT="${VAULT_KLAUT_STATIC_ROOT:-/var/lib/li-httpd/vault-klaut}"
VAULT_NODEPORT="${VAULT_NODEPORT:-30485}"
STORE_NAME="${VAULT_CLUSTER_SECRET_STORE:-homelab-vault}"

mkdir -p "$STATIC_ROOT"

vault_unsealed=0
vault_msg="Vault API unreachable on 127.0.0.1:${VAULT_NODEPORT}"
health_json="$(curl -sf "http://127.0.0.1:${VAULT_NODEPORT}/v1/sys/health?standbyok=true" 2>/dev/null || true)"
if [[ -n "$health_json" ]]; then
  if echo "$health_json" | grep -q '"sealed":false'; then
    vault_unsealed=1
    vault_msg="Vault unsealed (homelab OSS)"
  elif echo "$health_json" | grep -q '"sealed":true'; then
    vault_msg="Vault sealed — check VAULT_UNSEAL_KEY and vault-unseal secret"
  else
    vault_msg="Vault not initialized"
  fi
fi

css_ready=0
css_msg="ClusterSecretStore ${STORE_NAME} not found"
if command -v kubectl >/dev/null; then
  if kubectl get clustersecretstore "$STORE_NAME" >/dev/null 2>&1; then
    cond="$(kubectl get clustersecretstore "$STORE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    reason="$(kubectl get clustersecretstore "$STORE_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)"
    if [[ "$cond" == "True" ]]; then
      css_ready=1
      css_msg="ClusterSecretStore ${STORE_NAME} Ready"
    else
      css_msg="ClusterSecretStore ${STORE_NAME} not Ready (${reason:-unknown})"
    fi
  fi
fi

eso_json="[]"
if command -v kubectl >/dev/null && command -v python3 >/dev/null; then
  eso_json="$(kubectl get externalsecrets -A -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
out=[]
for i in d.get('items',[]):
  st=(i.get('status') or {}).get('conditions') or []
  ready=next((c.get('status') for c in st if c.get('type')=='Ready'),'Unknown')
  out.append({'namespace':i['metadata']['namespace'],'name':i['metadata']['name'],'ready':ready})
print(json.dumps(out))
" 2>/dev/null || echo '[]')"
fi

http_code=503
[[ "$vault_unsealed" -eq 1 && "$css_ready" -eq 1 ]] && http_code=200

cat >"${STATIC_ROOT}/status.json" <<EOF
{
  "vault_host": "vault.klaut.pro",
  "vault_mode": "oss",
  "cluster_secret_store": "${STORE_NAME}",
  "vault_unsealed": $( [[ "$vault_unsealed" -eq 1 ]] && echo true || echo false ),
  "eso_store_ready": $( [[ "$css_ready" -eq 1 ]] && echo true || echo false ),
  "ready": $( [[ "$http_code" -eq 200 ]] && echo true || echo false ),
  "message": "${vault_msg}; ${css_msg}",
  "external_secrets": ${eso_json},
  "docs": "https://github.com/cap-jmk-launchpad/homelab-k3s/blob/master/docs/vault-homelab.md"
}
EOF

cat >"${STATIC_ROOT}/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>vault.klaut.pro — homelab Vault</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 42rem; margin: 2rem auto; padding: 0 1rem; }
    .ok { color: #0a0; } .warn { color: #a60; }
    code { background: #f4f4f4; padding: 0.1em 0.3em; }
  </style>
</head>
<body>
  <h1>vault.klaut.pro</h1>
  <p>Self-hosted HashiCorp Vault OSS on k3s (Raft). Apps sync via External Secrets Operator.</p>
  <p class="$( [[ "$http_code" -eq 200 ]] && echo ok || echo warn )"><strong>Status:</strong> ${vault_msg}; ${css_msg}</p>
  <ul>
    <li><a href="/ui/">Vault UI</a> (via li-httpd)</li>
    <li><a href="/status.json">status.json</a></li>
    <li><a href="/healthz">healthz</a> (HTTP ${http_code} when unsealed + ESO store Ready)</li>
  </ul>
</body>
</html>
EOF

if [[ "$http_code" -eq 200 ]]; then
  printf 'ok\n' >"${STATIC_ROOT}/healthz"
else
  printf '%s\n' "${vault_msg}; ${css_msg}" >"${STATIC_ROOT}/healthz"
fi

echo "edge-vault-klaut-status: healthz=${http_code} (${vault_msg}; ${css_msg})"
echo "edge-vault-klaut-status: static files under ${STATIC_ROOT} — run edge-lis-apply.sh to reload"
