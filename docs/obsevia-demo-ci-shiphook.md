# Obsevia demo CI + Shiphook + Vault

Gated pipeline for **QROMA-DEMO**, **DUCAH**, and **DP-DEMO**:

1. GitHub Actions: install → test (Vitest + Playwright) → build
2. **Staging** (homelab k3s): POST Shiphook webhook on blackpearl
3. **Prod** (VPS1): SSH deploy after staging reports `[done] ok=true`

Pattern matches [majico.xyz Shiphook staging](https://github.com/cap-jmk-real/shiphook) and [homelab-k3s vault](vault-homelab.md).

## URLs

| Demo | Homelab staging | Prod (VPS1) |
|------|-----------------|-------------|
| QROMA | http://qroma.homelab.lan · NodePort **30584** | https://qroma.obsevia.com |
| DUCAH | http://ducah.homelab.lan · NodePort **30583** | https://ducah.obsevia.com |
| DP | http://dp.homelab.lan · NodePort **30582** | https://dp.obsevia.com |

WAN webhook host (GitHub Actions → homelab): `https://shiphook.obsevia.d3bu7.com/deploy/staging/{qroma|ducah|dp}`

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
| `VPS1_SSH_PRIVATE_KEY` | `HOMELAB_KEY` / `~/.ssh/obsevia_deploy` OpenSSH key | Prod SSH deploy |
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
- **Note:** For `gh secret set` you need admin on each repo or org-level secret management

Classic PAT alternative: scopes `repo`, `workflow`, `read:org`.

Store in `Obsevia/.env` as `GH_TOKEN` and `GITHUB_TOKEN` (same value). Never commit.

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

## Workflows

Each demo repo has `.github/workflows/ci-deploy.yml`:

- PR / push: test + build only
- Push to `main` / `master`: test → Shiphook staging → VPS1 prod SSH

Deploy scripts on blackpearl: [`scripts/obsevia-shiphook-deploy.sh`](../scripts/obsevia-shiphook-deploy.sh)
