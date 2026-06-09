# GitLab fast iteration (tokens, API bypass, Playwright)

Homelab GitLab runs on k3s NodePort **30481** behind **li-httpd** at `https://gitlab.lilangverse.xyz`. Day-to-day dev is faster when you pick the right path for each operation.

## Quick reference

| Task | Fast path | Why |
|------|-----------|-----|
| Mint / refresh PAT (default) | `npm run gitlab:auth` | Same as `gitlab:mint-pat` — ~30s, no browser |
| Browser session (UI tests) | `npm run gitlab:auth:browser` | Playwright login when edge render works |
| Raw NodePort login | — | **Avoid** — CSRF 422 (`external_url` is HTTPS) |
| API read (groups, projects) | `https://gitlab.lilangverse.xyz` + PAT | Edge GET works |
| API write / `git push` via API | `http://127.0.0.1:30481` from **blackpearl** | Edge HTTPS POST can hang or 400 for some bodies |
| Git smart HTTP (clone/push) | `https://gitlab.lilangverse.xyz` | Edge proxies POST for git-upload/receive-pack |
| Proxy byte gate (18/18 curl) | `npm run test:proxy` | `wc -c` == Content-Length per asset |
| Parallel load gate | `npm run test:edge-parallel` | 18 concurrent asset fetches |
| Render gate | `npm run test:edge-render` | Playwright CSS/JS acceptance |
| Full edge suite | `npm test` | proxy + parallel + render |

## Mint PAT / refresh auth (`npm run gitlab:auth` — ~30s)

From workstation (needs `KUBECONFIG=~/.kube/config-homelab`):

```bash
cd homelab-k3s
npm run gitlab:auth
# → homelab-k3s/.gitlab-token.local (gitignored)

# Or patch repo-root .env.local:
OUT_FILE=../.env.local npm run gitlab:auth
```

PowerShell:

```powershell
cd homelab-k3s
$env:OUT_FILE = "..\.env.local"
npm run gitlab:mint-pat
```

Manual rails runner on blackpearl (same mechanism):

```bash
kubectl exec -n gitlab gitlab-0 -- gitlab-rails runner \
  "t=PersonalAccessToken.new(user: User.find_by(username: 'root'), name: 'manual', scopes: [:api], expires_at: 1.year.from_now); t.save!; puts t.token[-4..]"
```

Root password (login only — not for API): `gitlab-secrets` key `GITLAB_ROOT_PASSWORD`:

```bash
kubectl -n gitlab get secret gitlab-secrets -o jsonpath='{.data.GITLAB_ROOT_PASSWORD}' | base64 -d
```

## Playwright auth (session reuse — when edge render works)

```bash
cd homelab-k3s
npm install
npm run gitlab:auth:browser      # edge HTTPS (host → 192.168.10.33)
npm run gitlab:auth:browser:pat  # login + create PAT in UI (edge POST must work)
```

Outputs:

- `test-results/gitlab-auth/storageState.json` — reuse with `storageState` in Playwright config
- `test-results/gitlab-auth/summary.json` — logged-in URL, base URL used

Environment:

| Variable | Default | Purpose |
|----------|---------|---------|
| `GITLAB_HOST` | `gitlab.lilangverse.xyz` | SNI / Host for edge |
| `EDGE_IP` | `192.168.10.33` | Chromium `--host-resolver-rules` MAP |
| `KUBECONFIG` | `~/.kube/config-homelab` | Root password lookup |
| `GITLAB_TOKEN_OUT` | `.gitlab-token.local` | PAT write target when using `gitlab:auth:pat` |

## API / git bypass (edge POST limitations)

**Symptom:** `curl` GET to `/api/v4/user` via edge returns **200**; POST (create MR, mint PAT via API) **hangs** or returns **400** from workstation or with `Host: gitlab.lilangverse.xyz` on raw NodePort.

**Cause:** Omnibus `external_url` is `https://gitlab.lilangverse.xyz`. Direct HTTP to NodePort with that `Host` without full reverse-proxy headers yields nginx **400**. Edge li-httpd relays GET reliably; large or POST API bodies through TLS relay may still fail on some builds — use NodePort for writes until edge gate is **TESTED**.

**Bypass from blackpearl:**

```bash
export GITLAB_TOKEN="$(grep GITLAB_TOKEN ~/staging/homelab-k3s/.gitlab-token.local | cut -d= -f2)"
curl -s -H "PRIVATE-TOKEN: $GITLAB_TOKEN" http://127.0.0.1:30481/api/v4/user
git -c http.extraHeader="PRIVATE-TOKEN: $GITLAB_TOKEN" push \
  http://127.0.0.1:30481/li-langverse/MY_REPO.git HEAD:main
```

Do **not** expose NodePort 30481 on Fritz; use only on LAN / SSH to blackpearl.

## GitLab Omnibus / edge config (current)

| Setting | Value | Location |
|---------|-------|----------|
| `external_url` | `https://gitlab.lilangverse.xyz` | `gitlab-secrets` → `omnibus.rb` |
| `trusted_proxies` | RFC1918 + loopback | `k8s/gitlab/configmap.yaml` |
| `nginx real_ip` | `X-Forwarded-For`, trusted RFC1918 | same |
| Edge routes | `POST /*` → `proxy:gitlab` | `k8s/edge/homelab.httpd.toml` |
| Registry | disabled in Omnibus | `registry['enable'] = false` |

No cluster change required for token minting. Fixing edge POST for JSON API is tracked via [public-edge-gitlab.md](public-edge-gitlab.md) acceptance gate (parallel 18/18 assets + POST relay).

## Typical workflow

```bash
# 1) Refresh token (workstation)
cd homelab-k3s && OUT_FILE=../.env.local npm run gitlab:mint-pat

# 2) Verify API read through edge
source ../.env.local  # or export GITLAB_TOKEN
curl -sk --resolve gitlab.lilangverse.xyz:443:192.168.10.33 \
  -H "PRIVATE-TOKEN: $GITLAB_TOKEN" https://gitlab.lilangverse.xyz/api/v4/user

# 3) API write / push from blackpearl when edge POST fails
ssh blackpearl 'curl -s -H "PRIVATE-TOKEN: '"$GITLAB_TOKEN"'" http://127.0.0.1:30481/api/v4/groups/li-langverse'

# 4) Edge proxy gates (from homelab-k3s/)
npm run test:proxy          # sequential 18/18 curl
npm run test:edge-parallel  # parallel 18/18 curl
npm run test:edge-render    # Playwright browser render
# or all three:
npm test

npm run gitlab:auth
```

## Related

- [public-edge-gitlab.md](public-edge-gitlab.md) — edge topology, acceptance gate
- [gitlab-homelab.md](gitlab-homelab.md) — Omnibus deploy, runners
- [README-edge-gitlab-render.md](../scripts/README-edge-gitlab-render.md) — Playwright render test
