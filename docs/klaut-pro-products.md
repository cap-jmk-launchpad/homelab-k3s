# klaut.pro products — three monetizable surfaces

**klaut.pro products** is the portfolio strategy: identify successful SaaS elsewhere, ship cloned or improved variants under the **klaut.pro** brand, and monetize them. Each sellable surface gets its own **Vault path**, **Supabase `platform_projects` row**, and **GitLab repo** (no shared secret blob across products).

| Product | Slug | Model |
|---------|------|--------|
| **GitHub security agent** | `sec-agent` | CodeRabbit-style security reviews on PRs |
| **Monetized search** | `search-api` | Metered agent search API |
| **Monetized vault** | `vault-api` | BYOK secrets API for agents and apps |

Control-plane architecture (search + secrets API, billing, hostnames) stays in [agentic-platform.md](agentic-platform.md). This doc is the **project matrix** and onboarding checklist.

## Products

| Product | Slug | Monetization | Stack dependency |
|---------|------|--------------|------------------|
| **GitHub security agent** | `sec-agent` | Subscription per org/repo; sec review on PRs (CodeRabbit-style for security) | GitHub App, homelab k3s runners, optional Supabase for usage; Vault for app credentials |
| **Monetized search** | `search-api` | Tiered search quota + overage ([search-klaut-pro.md](search-klaut-pro.md#suggested-tiers)) | SearXNG (`search.klaut.pro`), gateway `api.search.klaut.pro`, Redis, Supabase `platform_api_keys` |
| **Monetized vault** | `vault-api` | Tiered BYOK keys/seats; tenant secrets API | HCP Vault ([hcp-vault.md](hcp-vault.md)), control plane `api.klaut.pro`, ESO for hosted runners |

**Rule:** one Vault **project slug** per product for platform ops secrets. Customer BYOK stays under `secret/tenants/{tenant_id}/` (owned by **vault-api**, not mixed into `saas/*`).

---

## Vault path layout

KV v2 mount: `secret`. ESO `remoteRef` uses paths **without** the `data/` prefix.

| Class | Pattern | Used by |
|-------|---------|---------|
| **Platform ops (per product)** | `secret/saas/{slug}/{env}/` | `dev` \| `staging` \| `prod` — each product slug below |
| **Shared platform control plane** | `secret/saas/klaut-platform/prod/` | Stripe, narrow Vault admin token, gateway HMAC (cross-product) |
| **Tenant BYOK** | `secret/tenants/{tenant_id}/` | **vault-api** customers only |

| Product slug | Example platform path | Typical keys (names only) |
|--------------|----------------------|---------------------------|
| `sec-agent` | `secret/saas/sec-agent/staging` | `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`, `WEBHOOK_SECRET`, scanner tokens |
| `search-api` | `secret/saas/search-api/prod` | `REDIS_URL`, `STRIPE_SECRET`, gateway signing secret |
| `vault-api` | `secret/saas/vault-api/prod` | `VAULT_TOKEN` (tenant-write policy), `STRIPE_SECRET`, Postgres DSN |
| *(existing homelab)* | `secret/saas/agent-swarm/staging`, `secret/saas/majico/staging` | Internal apps — unchanged |

### Onboard each product (policy + ExternalSecret)

Requires `VAULT_ADDR` + `VAULT_TOKEN` in local `.env` ([hcp-vault.md](hcp-vault.md)). **Do not commit tokens or seeded `.env` files.**

```bash
cd homelab-k3s

# GitHub security agent — staging namespace
./scripts/hcp-vault-onboard-project.sh sec-agent staging sec-agent

# Search gateway — production
./scripts/hcp-vault-onboard-project.sh search-api prod search-gateway

# Vault / secrets control plane — production (namespace matches agentic-platform doc)
./scripts/hcp-vault-onboard-project.sh vault-api prod klaut-platform
```

Seed KV from a local env file (values never printed):

```bash
ENV_FILE=/path/to/sec-agent/.env.staging \
  ./scripts/hcp-vault-seed-project.sh sec-agent staging

ENV_FILE=/path/to/search-api/.env.prod \
  ./scripts/hcp-vault-seed-project.sh search-api prod

ENV_FILE=/path/to/vault-api/.env.prod \
  ./scripts/hcp-vault-seed-project.sh vault-api prod
```

Then apply generated manifests:

```bash
kubectl apply -f k8s/vault/projects/sec-agent/external-secret.yaml
kubectl apply -f k8s/vault/projects/search-gateway/external-secret.yaml
kubectl apply -f k8s/vault/projects/klaut-platform/external-secret.yaml
```

**Tenant onboarding (vault-api only):** add policy per `tenant_id` under `secret/tenants/{id}/` — extend [hcp-vault-onboard-project.sh](../scripts/hcp-vault-onboard-project.sh) or add `hcp-vault-onboard-tenant.sh` (see [agentic-platform.md](agentic-platform.md#secret-classes-and-vault-paths)). Control plane writes KV; customers use Secrets API, not admin tokens.

---

## Supabase `platform_projects`

Schema: [k8s/supabase/migrations/20260603120000_platform_tables.sql](../k8s/supabase/migrations/20260603120000_platform_tables.sql).

Seed rows (also in migration `20260603130000_platform_projects_seed.sql`):

```sql
INSERT INTO public.platform_projects (slug, name) VALUES
  ('sec-agent', 'GitHub Security Agent'),
  ('search-api', 'Klaut Search API'),
  ('vault-api', 'Klaut Vault API')
ON CONFLICT (slug) DO NOTHING;
```

Issue API keys with `project_id` → matching slug. Scopes examples: `search:read`, `secrets:read`, `sec:review` (enforce in each gateway).

Apply migrations after SQL changes ([supabase-launchpad.md](supabase-launchpad.md#platform-migrations)).

---

## GitLab repos (suggested)

Host: homelab GitLab CE ([gitlab-homelab.md](gitlab-homelab.md)) or GitHub org `cap-jmk-launchpad`.

| Product | Suggested repo | Notes |
|---------|----------------|-------|
| GitHub security agent | `launchpad/sec-agent` | GitHub App manifest, review workers, webhook handler |
| Monetized search | `launchpad/search-gateway` | Thin proxy: API key → Redis quota → SearXNG; homelab manifests stay in `homelab-k3s/k8s/searxng/` |
| Monetized vault | `launchpad/vault-api` | Secrets API + tenant CRUD; infra in `homelab-k3s/k8s/vault/` |

Keep **`homelab-k3s`** as the cluster/edge/Vault/Supabase runbook repo; product repos are application code and CI. (`launchpad/` here is the dev monorepo path on disk, not the product brand.)

---

## Hostnames (quick reference)

| Product | Public API / UI |
|---------|-----------------|
| sec-agent | GitHub App callbacks → your edge URL (e.g. `api.klaut.pro/webhooks/github`) |
| search-api | `api.search.klaut.pro` (metered); debug engine `search.klaut.pro` |
| vault-api | `api.klaut.pro/v1/secrets/*`; dashboard `dashboard.klaut.pro` |

---

## Build order

1. **search-api** — gateway + `platform_projects` row + Vault `search-api/prod` (proves metering).
2. **vault-api** — tenant paths + Secrets API + `vault-api/prod`.
3. **sec-agent** — GitHub App + `sec-agent/staging` (can ship after search/vault MVP).

Upgrade HCP to **Standard+** before paid tenant traffic ([hcp-vault.md#security-notes-homelab](hcp-vault.md#security-notes-homelab)).

---

## Related

- [agentic-platform.md](agentic-platform.md) — unified Klaut control plane
- [hcp-vault.md](hcp-vault.md) — HCP portal, ESO, onboard/seed scripts
- [search-klaut-pro.md](search-klaut-pro.md) — SearXNG deploy and search pricing
- [supabase-launchpad.md](supabase-launchpad.md) — self-hosted Supabase on k3s
