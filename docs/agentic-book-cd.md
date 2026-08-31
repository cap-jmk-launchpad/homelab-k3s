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
