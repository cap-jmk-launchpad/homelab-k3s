# Obsevia demo CI + Shiphook + Vault + VPS1 rolling prod

Gated pipeline for **QROMA-DEMO**, **DUCAH**, and **DP-DEMO**:

1. GitHub Actions: install → test (Vitest + Playwright) → build
2. **Staging** (homelab k3s): POST Shiphook webhook on blackpearl
3. **Prod** (VPS1): SSH rolling deploy after staging reports `[done] ok=true`

Pattern matches [majico.xyz Shiphook staging](https://github.com/cap-jmk-real/shiphook) and [homelab-k3s vault](vault-homelab.md).

## URLs

| Demo | Homelab staging | Prod (VPS1) |
|------|-----------------|-------------|
| QROMA | http://qroma.homelab.lan · NodePort **30584** | https://qroma.obsevia.com |
| DUCAH | http://ducah.homelab.lan · NodePort **30583** | https://ducah.obsevia.com |
| DP | http://dp.homelab.lan · NodePort **30582** | https://dp.obsevia.com |

WAN webhook host (GitHub Actions → homelab): `https://shiphook.obsevia.d3bu7.com/deploy/staging/{qroma|ducah|dp}`

## SSH credentials (canonical sources)

| Use | Canonical source | Notes |
|-----|------------------|-------|
| **GitHub Actions prod deploy** | Repo secret `VPS1_SSH_PRIVATE_KEY` | Synced from Vault `secret/saas/obsevia/staging` (see commit `9a839a7b`). Also set `VPS1_HOST`. |
| **Vault (source of truth)** | `secret/saas/obsevia/staging` → `VPS1_SSH_PRIVATE_KEY` | Read with homelab Vault OSS (`vault.klaut.pro`) or `scripts/sync-staging-secrets.sh`. |
| **Local Windows deploy** | `Obsevia/.env` → `SSH_KEY_PATH` or `Obsevia/.ssh/obsevia_deploy` | `QROMA-DEMO/scripts/lib/obsevia-ssh.ps1` resolves key paths in order. |
| **Homelab LAN (blackpearl)** | `beelink-cleanup/homelab` | Not authorized on VPS1 by default; use for k3s staging only. |
| **Password fallback** | `Obsevia/.env` → `VPS1_PASSWORD` | Used by `obsevia-ssh.ps1` via plink when no key is found. |
| **Key backup** | `beelink-cleanup/.backups/keys/` | Timestamped copies of homelab keys; not the VPS1 deploy key. |

Never commit private keys. `.env` / `.env.local` stay gitignored.

All three demo repos have `VPS1_SSH_PRIVATE_KEY` and `VPS1_HOST` in GitHub Actions (2026-06-08).

## Vault (homelab OSS)

| Source | Path / keys |
|--------|-------------|
| Vault UI | `https://vault.klaut.pro` (NodePort 30485 on blackpearl) |
| Local bootstrap | `launchpad/.env` or `homelab-k3s/.env`: `VAULT_ADDR`, `VAULT_TOKEN`, `VAULT_UNSEAL_KEY` |
| KV layout | `secret/saas/{slug}/staging/` — seed via `scripts/hcp-vault-seed-project.sh` |
| Blackpearl runtime | `~/staging/secrets/obsevia.env` (synced from PC, never commit) |

Sync local Obsevia creds to blackpearl:

```bash
ENV_FILE=../../Obsevia/.env STAGING_HOST=blackpearl STAGING_KEY=~/.ssh/homelab \
  bash scripts/sync-staging-secrets.sh
# Then on blackpearl: cp ~/staging/secrets/.env.staging ~/staging/secrets/obsevia.env
```

### Sync Vault → GitHub secrets

```bash
gh secret set VPS1_SSH_PRIVATE_KEY --repo obsevia-compliance/DUCAH < keyfile
gh secret set VPS1_HOST --repo obsevia-compliance/DUCAH --body "82.165.195.105"
# Repeat for QROMA-DEMO and DP-DEMO repos
```

## GitHub Secrets (names only)

Set per repo under **obsevia-compliance** → Settings → Secrets → Actions.
Populate from `Obsevia/.env`, Vault KV, or `scripts/sync-obsevia-github-secrets.ps1`.

| Secret | Source env / vault key | Purpose |
|--------|------------------------|---------|
| `NEXT_PUBLIC_SUPABASE_URL` | `NEXT_PUBLIC_SUPABASE_URL` | CI build + e2e |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | CI build + e2e |
| `SUPABASE_SERVICE_ROLE_KEY` | `SUPABASE_SERVICE_ROLE_KEY` | E2E globalSetup (QROMA) |
| `SUPABASE_TEST_EMAIL` | `SUPABASE_TEST_EMAIL` | Playwright auth |
| `SUPABASE_TEST_PASSWORD` | `SUPABASE_TEST_PASSWORD` | Playwright auth |
| `SHIPHOOK_STAGING_URL` | fixed per demo (see below) | Staging webhook |
| `SHIPHOOK_STAGING_SECRET` | `~/staging/shiphook-server/.shiphook.staging.secret` on blackpearl | `X-Shiphook-Secret` header |
| `VPS1_SSH_PRIVATE_KEY` | Vault `secret/saas/obsevia/staging` or `~/.ssh/obsevia_deploy` | Prod SSH deploy |
| `VPS1_HOST` | `VPS1_HOST` (optional, default `82.165.195.105`) | Prod target |
| `GH_TOKEN` | `GH_TOKEN` or `GITHUB_TOKEN` | Private repo clone on VPS1 |

**Per-demo `SHIPHOOK_STAGING_URL`:**

- QROMA-DEMO: `https://shiphook.obsevia.d3bu7.com/deploy/staging/qroma`
- DUCAH: `https://shiphook.obsevia.d3bu7.com/deploy/staging/ducah`
- DP-DEMO: `https://shiphook.obsevia.d3bu7.com/deploy/staging/dp`

### GitHub PAT (`GH_TOKEN` / `GITHUB_TOKEN`)

Fine-grained PAT (recommended) from https://github.com/settings/tokens:

- **Resource owner:** your account or `obsevia-compliance`
- **Repositories:** `QROMA-DEMO`, `DUCAH`, `DP-DEMO`, `homelab-k3s`
- **Permissions:** Contents (Read), Actions (Read and write secrets), Metadata (Read)

Store in `Obsevia/.env` as `GH_TOKEN` and `GITHUB_TOKEN` (same value). Never commit.

## VPS1 zero-downtime rolling deploy

Production demos on VPS1 use **Docker Compose + host nginx** (not k8s). Pattern:

1. **Two replicas** per demo (`*-1` / `*-2`) on adjacent host ports
2. **nginx upstream** with `least_conn`, `max_fails`, `proxy_next_upstream`
3. **Rolling script** `scripts/lib/rolling-compose-deploy.sh`:
   - `docker compose build` (first replica service)
   - For each replica: `up -d --no-deps --force-recreate <service>` → wait until healthy
   - Never `docker compose down`
4. **nginx reload** (`nginx -t && systemctl reload nginx`) only after replicas healthy — reload is graceful for existing connections

| Demo | Domain | Replicas | Host ports | Upstream |
|------|--------|----------|------------|----------|
| DUCAH | ducah.obsevia.com | duca-demo-1, duca-demo-2 | 3030, 3031 | `duca_demo_upstream` |
| DP-DEMO | dp.obsevia.com | dp-demo-1, dp-demo-2 | 3020, 3021 | `dp_demo_upstream` |
| QROMA | qroma.obsevia.com | qroma-demo-1, qroma-demo-2 | 30184, 30185 | `qroma_demo_upstream` |

Entry point on VPS1: `deploy_staging.sh` in each repo clone under `/root/<demo>/`.

### Manual rolling test

While deploy runs, poll the public health URL — responses should stay 2xx/3xx (no 502 gap):

```bash
while true; do
  date -Is
  curl -fsS -o /dev/null -w "%{http_code}\n" https://ducah.obsevia.com/login || echo FAIL
  sleep 1
done
```

## One-time Shiphook on blackpearl

1. Install Shiphook (see `majico.xyz/scripts/staging/setup-shiphook-blackpearl.sh`).
2. Merge apps from [`shiphook.obsevia-demos.yaml.example`](../shiphook.obsevia-demos.yaml.example) into `~/staging/shiphook-server/shiphook.yaml`.
3. Merge [`k8s/edge/obsevia-demos-shiphook.httpd.toml`](../k8s/edge/obsevia-demos-shiphook.httpd.toml) into edge config; run `edge-lis-apply.sh`.
4. DNS: `A shiphook.obsevia.d3bu7.com` → homelab WAN IP (or Fritz port-forward to blackpearl :80).
5. Export `SHIPHOOK_STAGING_SECRET` to GitHub org/repo secrets.

Test locally (on blackpearl):

```bash
SECRET="$(cat ~/staging/shiphook-server/.shiphook.staging.secret)"
curl -N -X POST "http://127.0.0.1/deploy/staging/qroma" \
  -H "Host: shiphook.obsevia.d3bu7.com" \
  -H "X-Shiphook-Secret: ${SECRET}" \
  -H "Content-Type: application/json" \
  -d '{"env":{"GH_TOKEN":"..."}}'
```

## Async staging deploy (li-httpd timeout fix)

Homelab **li-httpd** closes idle upstream connections at ~3m36s. Obsevia demo docker builds take 4–6 minutes, so synchronous `?format=json` through the WAN edge fails with `curl: (52) Empty reply from server` even though Shiphook on `:3141` completes the deploy.

**Fix (Option A):** Shiphook on blackpearl accepts `?format=json&async=1` and returns **HTTP 202** immediately:

```json
{"status":"accepted","jobId":"<uuid>","app":"qroma-staging"}
```

The docker build + k3s import runs in the background. GitHub Actions `scripts/ci/trigger-shiphook-staging.sh` uses async mode with a 60s curl timeout and treats `202` + `status=accepted` as success.

**li-httpd edge quirks:**
- Use `Authorization: Bearer <secret>` from CI (more reliable than `X-Shiphook-Secret` through the edge).
- Do **not** send a JSON POST body through the edge — li-httpd deadlocks on proxied bodies. CI triggers with an empty POST; blackpearl reads `GH_TOKEN` and Supabase keys from `~/staging/secrets/obsevia.env` inside `obsevia-shiphook-deploy.sh`.

Apply or re-apply the server patch on blackpearl:

```bash
python3 ~/staging/homelab-k3s/scripts/patch-shiphook-async.py
sudo systemctl restart shiphook-staging.service
```

Verify through the edge (should return in &lt;1s):

```bash
SECRET="$(cat ~/staging/shiphook-server/.shiphook.staging.secret)"
curl -sS -m 30 -X POST "http://127.0.0.1:80/deploy/staging/qroma?format=json&async=1" \
  -H "Host: shiphook.obsevia.d3bu7.com" \
  -H "X-Shiphook-Secret: ${SECRET}" \
  -H "Content-Type: application/json" \
  -d '{"env":{"SKIP_BUILD":"1","SKIP_IMAGE_IMPORT":"1"}}' \
  -w "\nHTTP:%{http_code}\n"
```

Direct `:3141` still supports synchronous `?format=json` for interactive debugging.

## Workflows

Each demo repo has `.github/workflows/ci-deploy.yml`:

- PR / push: test + build only
- Push to `main` / `master`: test → Shiphook staging → **VPS1 prod rolling SSH deploy**

Deploy scripts on blackpearl: [`scripts/obsevia-shiphook-deploy.sh`](../scripts/obsevia-shiphook-deploy.sh)

Homelab k8s staging uses **Deployment rollingUpdate** (`maxUnavailable: 0`) — separate from VPS1 Docker rolling.

## Related docs

- [staging-duca-demo-homelab.md](./staging-duca-demo-homelab.md)
- [homelab-ssh-keys.md](./homelab-ssh-keys.md)
- [vault-homelab.md](./vault-homelab.md)
- Obsevia `obsevia-kubernetes/docs/ha-docker-replicas.md`
