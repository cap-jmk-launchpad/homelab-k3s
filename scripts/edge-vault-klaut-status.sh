#!/usr/bin/env bash
# Generate vault.klaut.pro static status + /healthz Caddy snippet from ClusterSecretStore readiness.
set -euo pipefail

ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
STATIC_ROOT="${VAULT_KLAUT_STATIC_ROOT:-/var/lib/caddy/vault-klaut}"
CADDY_SNIP="${VAULT_KLAUT_CADDY_SNIP:-/etc/caddy/vault-klaut-health.caddy}"
HCP_PORTAL="${HCP_VAULT_PORTAL_URL:-https://portal.cloud.hashicorp.com/services/vault}"

mkdir -p "$STATIC_ROOT"

css_ready=0
css_msg="ClusterSecretStore hcp-vault not found"
if command -v kubectl >/dev/null; then
  if kubectl get clustersecretstore hcp-vault >/dev/null 2>&1; then
    cond="$(kubectl get clustersecretstore hcp-vault -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
    reason="$(kubectl get clustersecretstore hcp-vault -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null || true)"
    if [[ "$cond" == "True" ]]; then
      css_ready=1
      css_msg="ClusterSecretStore hcp-vault Ready"
    else
      css_msg="ClusterSecretStore hcp-vault not Ready (${reason:-unknown})"
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
[[ "$css_ready" -eq 1 ]] && http_code=200

cat >"${STATIC_ROOT}/status.json" <<EOF
{
  "vault_host": "vault.klaut.pro",
  "hcp_vault": "cloud-hosted (not a local pod)",
  "cluster_secret_store": "hcp-vault",
  "ready": $( [[ "$css_ready" -eq 1 ]] && echo true || echo false ),
  "message": "${css_msg}",
  "external_secrets": ${eso_json},
  "docs": "https://github.com/cap-jmk-launchpad/homelab-k3s/blob/master/docs/hcp-vault.md"
}
EOF

cat >"${STATIC_ROOT}/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <title>vault.klaut.pro — HCP Vault status</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 42rem; margin: 2rem auto; padding: 0 1rem; }
    .ok { color: #0a0; } .warn { color: #a60; }
    code { background: #f4f4f4; padding: 0.1em 0.3em; }
  </style>
</head>
<body>
  <h1>vault.klaut.pro</h1>
  <p>HCP Vault Dedicated (secrets in cloud KV). Apps sync via External Secrets Operator.</p>
  <p class="$( [[ "$css_ready" -eq 1 ]] && echo ok || echo warn )"><strong>ESO:</strong> ${css_msg}</p>
  <ul>
    <li><a href="${HCP_PORTAL}">HCP Vault portal</a></li>
    <li><a href="/status.json">status.json</a></li>
    <li><a href="/healthz">healthz</a> (HTTP ${http_code} when store Ready)</li>
  </ul>
</body>
</html>
EOF

if [[ "$css_ready" -eq 1 ]]; then
  cat >"$CADDY_SNIP" <<'EOF'
handle /healthz {
	respond "ok" 200
}
EOF
else
  cat >"$CADDY_SNIP" <<EOF
handle /healthz {
	respond "${css_msg}" 503
}
EOF
fi

echo "edge-vault-klaut-status: healthz=${http_code} (${css_msg})"
