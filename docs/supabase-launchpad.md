# Launchpad Supabase (k3s, internal)

Self-hosted Supabase for Launchpad prototyping in namespace `supabase` on blackpearl. No public edge route (`db.klaut.pro` is out of scope).

## Stack

| Service | Purpose | Access |
|---------|---------|--------|
| `db` | `supabase/postgres` + 10Gi PVC | cluster `db:5432` |
| `auth` | GoTrue | via Kong `/auth/v1` |
| `rest` | PostgREST | via Kong `/rest/v1` |
| `meta` | Studio SQL metadata | via Kong `/pg` (service role) |
| `studio` | Dashboard UI | via Kong `/` (basic auth) |
| `kong` | API gateway | **NodePort 30480** |

Realtime, Storage, Edge Functions, and Logflare analytics are omitted to stay near ~2GiB RAM on blackpearl (`NEXT_PUBLIC_ENABLE_LOGS=false` in Studio).

## Credentials

Secrets live in:

1. **launchpad** `../.env` (from repo root: `launchpad/.env`) — source of truth for redeploys
2. Kubernetes `supabase-secrets` in namespace `supabase`

Regenerate only when needed:

```bash
SUPABASE_REGENERATE_SECRETS=1 ./scripts/k8s-supabase-secret.sh
```

## Deploy

From homelab-k3s (Git Bash / WSL / blackpearl):

```bash
# On blackpearl (kubectl local)
LAUNCHPAD_ENV=~/launchpad/.env ./scripts/k8s-supabase-secret.sh
./scripts/k8s-supabase-db-bootstrap.sh   # first deploy / after POSTGRES_PASSWORD change
./scripts/k8s-supabase-apply.sh

# From PC via SSH (rsync manifests + .env, run on blackpearl)
SUPABASE_REMOTE=1 STAGING_HOST=blackpearl STAGING_KEY=../beelink-cleanup/homelab \
  LAUNCHPAD_ENV=../../launchpad/.env ./scripts/k8s-supabase-apply.sh
```

## Access Studio / API

```bash
# LAN NodePort (blackpearl IP)
open http://192.168.10.33:30480/

# Port-forward from any machine with kubeconfig/SSH
kubectl -n supabase port-forward svc/kong 54321:8000
# Studio + API: http://127.0.0.1:54321/  (dashboard basic auth from .env)
```

Use `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD` and `ANON_KEY` / `SERVICE_ROLE_KEY` from `.env` (never commit).

## Backups

- **Weekly** CronJob `supabase-backup` (Sunday 03:00 UTC) → PVC `supabase-backups` on blackpearl (`~/homelab-backups` path via local-path volume)
- **Daily** prune CronJob deletes folders older than **30 days**
- On-demand: `./scripts/k8s-supabase-backup.sh`

```bash
# List backup timestamps
./scripts/k8s-supabase-restore.sh

# Restore (scales API down briefly)
BACKUP_TS=20260603T030000Z ./scripts/k8s-supabase-restore.sh
```

Host copy (optional): mount or `kubectl cp` from pod with PVC mounted under `/backups/<TS>/postgres.dump`.

## Platform migrations

SQL: `k8s/supabase/migrations/20260603120000_platform_tables.sql` (`platform_projects`, `platform_api_keys`). klaut.pro product seed rows: `20260603130000_platform_projects_seed.sql` — see [klaut-pro-products.md](klaut-pro-products.md).

Re-run after SQL changes:

```bash
kubectl -n supabase delete job supabase-migrate --ignore-not-found
kubectl apply -k k8s/supabase/
kubectl -n supabase wait --for=condition=complete job/supabase-migrate --timeout=300s
```

## .env keys (names only)

`SUPABASE_NAMESPACE`, `SUPABASE_PUBLIC_URL`, `SUPABASE_URL`, `API_EXTERNAL_URL`, `SITE_URL`, `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_PASSWORD`, `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL`, `DATABASE_URL`, `GOTRUE_DB_DATABASE_URL`, `PGRST_DB_URI`, `POSTGRES_BACKEND_URL`, `DASHBOARD_USERNAME`, `DASHBOARD_PASSWORD`, `SECRET_KEY_BASE`, `PG_META_CRYPTO_KEY`, `VAULT_ENC_KEY`, `LOGFLARE_PUBLIC_ACCESS_TOKEN`, `LOGFLARE_PRIVATE_ACCESS_TOKEN`, `KONG_NODEPORT`

See also [agentic-platform.md](agentic-platform.md) for the wider Klaut control-plane design.
