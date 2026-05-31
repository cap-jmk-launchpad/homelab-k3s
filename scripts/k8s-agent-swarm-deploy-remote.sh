#!/usr/bin/env bash
set -euo pipefail
cd ~/beelink-cleanup

JWT=$(kubectl get secret agent-swarm-db-secrets -n agent-swarm -o jsonpath='{.data.JWT_SECRET}' | base64 -d)
PG=$(kubectl get secret agent-swarm-db-secrets -n agent-swarm -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)

_keys=$(JWT_SECRET="$JWT" POSTGRES_PASSWORD="$PG" SUPABASE_URL='http://postgrest:54321' SUPABASE_DB_HOST='postgres' python3 - <<'PY'
import os, hmac, hashlib, json, base64
secret = os.environ["JWT_SECRET"].encode()
exp = 1983812996

def b64url(obj):
    return base64.urlsafe_b64encode(json.dumps(obj, separators=(",", ":")).encode()).rstrip(b"=").decode()

def sign(role):
    header = b64url({"alg": "HS256", "typ": "JWT"})
    payload = b64url({"iss": "supabase-demo", "role": role, "exp": exp})
    sig = base64.urlsafe_b64encode(
        hmac.new(secret, f"{header}.{payload}".encode(), hashlib.sha256).digest()
    ).rstrip(b"=").decode()
    return f"{header}.{payload}.{sig}"

pg = os.environ["POSTGRES_PASSWORD"]
print("SUPABASE_URL=http://postgrest:54321")
print(f"SUPABASE_ANON_KEY={sign('anon')}")
print(f"SUPABASE_SERVICE_ROLE_KEY={sign('service_role')}")
print(f"SUPABASE_DB_URL=postgresql://postgres:{pg}@postgres:5432/postgres")
PY
)

set -a
CURSOR_API_KEY="$(grep -E '^CURSOR_API_KEY=' ~/beelink-cleanup/.env.agents | head -1 | cut -d= -f2- | tr -d '\r' || true)"
GH_TOKEN="$(grep -E '^GH_TOKEN=' ~/beelink-cleanup/.env.agents | head -1 | cut -d= -f2- | tr -d '\r' || true)"
set +a

args=()
[[ -n "${CURSOR_API_KEY:-}" ]] && args+=(--from-literal=CURSOR_API_KEY="$CURSOR_API_KEY")
[[ -n "${GH_TOKEN:-}" ]] && args+=(--from-literal=GH_TOKEN="$GH_TOKEN")
while IFS= read -r line; do
  key="${line%%=*}"
  val="${line#*=}"
  args+=(--from-literal="$key=$val")
done <<< "$_keys"

kubectl -n agent-swarm delete secret agent-swarm-secrets --ignore-not-found
kubectl -n agent-swarm create secret generic agent-swarm-secrets "${args[@]}"
echo "==> app secret ok (${#args[@]} keys)"

kubectl apply -k k8s/agent-swarm/
kubectl -n agent-swarm wait --for=condition=ready pod -l app=postgres --timeout=300s
kubectl -n agent-swarm wait --for=condition=complete job/agent-swarm-db-migrate --timeout=600s
kubectl -n agent-swarm rollout status deployment/postgrest --timeout=300s

kubectl -n agent-swarm patch deployment agents-dashboard --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/nodeSelector/kubernetes.io~1hostname","value":"deck"},
  {"op":"replace","path":"/spec/template/spec/volumes/0/hostPath/path","value":"/home/s4il0r/li-langverse"}
]'
kubectl -n agent-swarm patch deployment agents-async-swarm --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/nodeSelector/kubernetes.io~1hostname","value":"deck"},
  {"op":"replace","path":"/spec/template/spec/volumes/0/hostPath/path","value":"/home/s4il0r/li-langverse"}
]'

kubectl -n agent-swarm rollout status deployment/agents-dashboard --timeout=600s
kubectl -n agent-swarm rollout status deployment/agents-async-swarm --timeout=600s
kubectl -n agent-swarm get pods -o wide
