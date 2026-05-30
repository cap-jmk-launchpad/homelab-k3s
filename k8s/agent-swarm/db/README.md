# In-cluster database (Postgres + PostgREST)

Supabase-compatible control-plane API inside the `agent-swarm` namespace.

| Service | K8s name | Port | Node |
|---------|----------|------|------|
| Postgres 15 | `postgres` | 5432 (cluster) | **blackpearl** (StatefulSet + 5Gi PVC) |
| PostgREST | `postgrest` | 54321 (cluster), **30421** (NodePort) | blackpearl |
| Migrations | Job `agent-swarm-db-migrate` | — | runs once per schema version |

Apps use `SUPABASE_URL=http://postgrest:54321` (in-cluster DNS).

JWT keys (`SUPABASE_SERVICE_ROLE_KEY`, etc.) are derived from `JWT_SECRET` in `agent-swarm-db-secrets` — same algorithm as local `supabase start`.

## Secrets

```bash
./scripts/k8s-agent-swarm-db-secret.sh          # Postgres + JWT
./scripts/k8s-agent-swarm-secret.sh /path/.env    # app + derived Supabase keys
```

## Migrations

SQL files are vendored under `db/migrations/`. When `li-cursor-agents` migrations change:

```bash
./scripts/k8s-agent-swarm-sync-migrations.sh
kubectl delete job agent-swarm-db-migrate -n agent-swarm
kubectl apply -k k8s/agent-swarm/
kubectl wait --for=condition=complete job/agent-swarm-db-migrate -n agent-swarm --timeout=600s
```

## Reset database (destructive)

```bash
kubectl delete job agent-swarm-db-migrate -n agent-swarm --ignore-not-found
kubectl delete statefulset postgres -n agent-swarm --cascade=orphan
kubectl delete pvc data-postgres-0 -n agent-swarm
kubectl apply -k k8s/agent-swarm/
```

## What is not included

- Supabase Studio, Auth, Storage — not needed for the control plane
- Host Docker Supabase — replaced by this stack
