# agentic-book.org CD via Shiphook (M1)

Agentic-book deploys to `blackpearl` (k3s ns `agentic-book`) through the
homelab Shiphook server, the same pattern as the Obsevia demos (see
[`obsevia-demo-ci-shiphook.md`](./obsevia-demo-ci-shiphook.md)):

```
GitHub Actions (web-deploy.yml)
  → POST https://shiphook.obsevia.d3bu7.com/deploy/agentic-book?format=json   (X-Shiphook-Secret)
  → Shiphook on blackpearl (:3141): git pull repoPath → run scripts/agentic-book-shiphook-deploy.sh
  → runScript: kubectl -n agentic-book set image deployment/agentic-app app=…web:main-<sha8> && rollout status
```

The GitHub workflow only **builds + pushes** the image to GHCR and **triggers**
Shiphook; `kubectl`/kubeconfig never leaves `blackpearl`.

## GitHub repo secrets

| Secret | Value |
|--------|-------|
| `SUPABASE_URL` | `https://supabase.agentic-book.org` |
| `SUPABASE_ANON_KEY` | anon key from `supabase-secrets` |
| `SHIPHOOK_DEPLOY_URL` | `https://shiphook.obsevia.d3bu7.com/deploy/agentic-book` |
| `SHIPHOOK_DEPLOY_TOKEN` | per-route Shiphook secret (mint below) |

Keep the GHCR package **private**. k3s pulls on `blackpearl` using the
`ghcr-regcred` imagePullSecret that the runScript creates idempotently from the
server-side PAT in `~/staging/secrets/agentic-book.env` (secrets `GHCR_USERNAME`
/ `GHCR_EMAIL` / `GHCR_TOKEN`, chmod 600 — never committed). CI pushes with its
own `GITHUB_TOKEN` (`packages: write`), so no token is needed in CI at all.

## One-time server setup (run on `blackpearl`)

1. **Clone agentic-book** (Shiphook `git pull`s this for the commit SHA):
    ```bash
    git clone https://github.com/agentic-book-org/agentic-book.git ~/staging/agentic-book
    # track main so `git pull` fast-forwards:
    cd ~/staging/agentic-book && git checkout main && git branch --set-upstream-to=origin/main main
    ```

2. **Shiphook runScript** already lives in this repo at
   `scripts/agentic-book-shiphook-deploy.sh` — no copy needed. The server runs it
   via the absolute path in the route below.

3. **Add the route** to the server's Shiphook config
   (`~/staging/shiphook-server/shiphook.yaml`) under `apps:`:
   ```yaml
    - name: agentic-book
      host: shiphook.obsevia.d3bu7.com
      path: /deploy/agentic-book
      repoPath: /home/s4il0r/staging/agentic-book
      runScript: bash /home/s4il0r/staging/homelab-k3s/scripts/agentic-book-shiphook-deploy.sh
      runTimeoutMs: 1800000
      secret: <DEPLOY_TOKEN>
    ```

4. **Mint the deploy secret** (same value in `secret:` above AND the GitHub
   secret `SHIPHOOK_DEPLOY_TOKEN`). Generate a strong token:
   ```bash
   tr -d -c 'a-zA-Z0-9' </dev/urandom | head -c 32 | sed 's/$/\\\n/' > ~/.shiphook.agentic-book.secret
   cat ~/.shiphook.agentic-book.secret          # use this value...
    gh secret set SHIPHOOK_DEPLOY_TOKEN -R agentic-book-org/agentic-book < ~/.shiphook.agentic-book.secret
   # ...and paste it into the route's `secret:` field above.
   ```
   Alternatively, omit `secret:` from the route and let Shiphook auto-generate
   one into `~/agentic-book/.shiphook/…<hash>.secret`; `cat` it and set
   `SHIPHOOK_DEPLOY_TOKEN` from it.

5. **Apply the web Service** (`agentic-svc`, NodePort 30620, selector `app=agentic-app`) once —
    it already exists in ns `agentic-book`, only recreate if lost.

6. **Edge routing** (public HTTPS for the Shiphook webhook):
    - `k8s/edge/nginx-shiphook-obsevia.conf` ships the `shiphook.obsevia.d3bu7.com` vhost
      (`:80` ACME webroot + proxy, `:443` ssl proxy → `127.0.0.1:3141`), included from
      `k8s/edge/nginx-gitlab-edge.conf`.
    - LE cert for `shiphook.obsevia.d3bu7.com` (webroot `/var/lib/li-httpd`, auto-renews).
    - Deploy with `sudo bash scripts/edge-nginx-apply.sh` — **not** a manual edit of
      `/etc/nginx/gitlab-edge/nginx.conf` (the watchdog re-applies from the repo source).

7. **Watchdog**: the `agentic-book` row is in
    `k8s/monitoring/cluster-watchdog/services.conf`; deploy it via
    `sudo bash scripts/deploy-cluster-watchdog.sh` (or re-copy services.conf + restart the
    timer). It probes `127.0.0.1:30620/api/books` and restarts pods on failure.

## Verify

```bash
# from blackpearl
kubectl -n agentic-book get deploy agentic-app
kubectl -n agentic-book rollout status deployment/agentic-app --timeout=180s
# Shiphook self-test (route + secret must exist)
TOKEN="$(grep -oE 'secret: .*' ~/staging/shiphook-server/shiphook.yaml | head -1 | cut -d' ' -f2)"
curl -sS -m 60 -X POST "https://shiphook.obsevia.d3bu7.com/deploy/agentic-book?format=json" \
  -H "X-Shiphook-Secret: $TOKEN" -H "Authorization: Bearer $TOKEN" -d '{}' | tail -3
# expect: [done] ok=true agentic-book-web ghcr.io/agentic-book-org/agentic-book-web:main-<sha>
```
## Troubleshooting: `/auth/callback` 502s (incident 2026-09-06/07)

Two stacked edge bugs produced Bad Gateway on the Google sign-in callback.
Neither was the app, the cert, or the Supabase config — both lived in
`k8s/edge/`. Documented here so the next 502 on this route is diagnosed
in minutes, not hours.

### Bug 1 — stale upstream port (immediate 502, `connect() failed (111)`)

`k8s/edge/nginx-agentic-book-web.conf` pointed `upstream agentic_book_web`
at `127.0.0.1:30608`, citing a Service `agentic-book-web` in namespace
`agentic-book-supabase` that does not exist. The live Service is
`agentic-svc` in namespace `agentic-book`, NodePort **30620** (healthy
endpoints, direct 200). nginx → dead port = instant 502.

Contributors to the drift:
- the deploy script never installed this per-app file (no `install` line),
  so `/etc` held a stale copy;
- a legacy inline `:443` block for the same `server_name` in
  `nginx-gitlab-edge.conf` (proxy → `upstream agentic_book` → `:30620`)
  shadowed the broken per-app file, so traffic worked *by accident*.

Fix (commit `f91cfc0`): upstream `30608 → 30620`; removed the legacy inline
blocks + unused upstream; added the per-app include (single source of truth);
added the missing `install` line to `scripts/edge-nginx-apply.sh`.

### Bug 2 — upstream response headers too big (502 *after* login succeeds)

With Bug 1 fixed, a fresh Google login reached the app, the PKCE exchange
succeeded — and nginx still 502d. Error log:
`upstream sent too big header while reading response header from upstream,
upstream: http://127.0.0.1:30620/auth/callback`.
A successful `exchangeCodeForSession` answers with several large `Set-Cookie`
headers (access + refresh JWTs), overflowing nginx's default 4k/8k
`proxy_buffer_size`.

Fix (commit `becdb76`): `proxy_buffer_size 32k; proxy_buffers 8 32k;
proxy_busy_buffers_size 64k;` on `location /` of
`k8s/edge/nginx-agentic-book-web.conf`. See the WHY comment inline there.
Do not lower these without re-testing a real Google sign-in.

### Watchdog coverage (no silent regressions)

- `check_nginx_upstreams()` (`scripts/cluster-watchdog.sh`): every
  `server 127.0.0.1:PORT` in live `nginx -T` must TCP-connect or match a
  k8s NodePort with endpoints. Catches Bug-1-class drift (stale port /
  renamed Service). Streak≥2 → CRIT with remediation; never auto-rewrites
  nginx, never restarts pods for this class.
- `check_nginx_errorlog()`: tails `gitlab-edge-error.log` for response-path
  fatals (`too big header`, `prematurely closed`) — the Bug-2 signature.
  `connect() failed` is deliberately excluded (owned by the check above).
  Alert-only, never heals.
- `check_agentic_book_auth()`: probes `/`, `/account`, and Supabase
  `/auth/v1/versions`; restarts `agentic-app` only when the Service has
  zero endpoints, otherwise logs `EDGE misroute suspected`.

### Verify after any edge change here

```bash
# from blackpearl
curl -s -o /dev/null -w "/: %{http_code} verify=%{ssl_verify_result}\n" \
  --resolve "agentic-book.org:443:127.0.0.1" "https://agentic-book.org/"
curl -s -o /dev/null -w "/auth/callback: %{http_code} verify=%{ssl_verify_result}\n" \
  --resolve "agentic-book.org:443:127.0.0.1" \
  "https://agentic-book.org/auth/callback?code=probe&next=/account"
# expect: 200, and 307 to /account?error= (app alive; the probe code is fake)
# a REAL login must be tested with a fresh Google click (codes are single-use)
sudo journalctl -u nginx-gitlab-edge --since "10 min ago" --no-pager \
  | grep -iE "emerg|too big header" || echo "edge clean"
```
