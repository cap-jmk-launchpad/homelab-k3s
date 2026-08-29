# agentic-book.org CD via Shiphook (M1)

Agentic-book deploys to `blackpearl` (k3s `agentic-book-supabase`) through the
homelab Shiphook server, the same pattern as the Obsevia demos (see
[`obsevia-demo-ci-shiphook.md`](./obsevia-demo-ci-shiphook.md)):

```
GitHub Actions (web-deploy.yml)
  → POST https://shiphook.agentic-book.org/deploy/agentic-book?format=json   (X-Shiphook-Secret)
  → Shiphook on blackpearl (:3141): git pull repoPath → run scripts/agentic-book-shiphook-deploy.sh
  → runScript: kubectl set image deployment/agentic-agentic-book-web …:main-<sha> && rollout status
```

The GitHub workflow only **builds + pushes** the image to GHCR and **triggers**
Shiphook; `kubectl`/kubeconfig never leaves `blackpearl`.

## GitHub repo secrets

| Secret | Value |
|--------|-------|
| `SUPABASE_URL` | `https://supabase.agentic-book.org` |
| `SUPABASE_ANON_KEY` | anon key from `supabase-secrets` |
| `SHIPHOOK_DEPLOY_URL` | `https://shiphook.agentic-book.org/deploy/agentic-book` |
| `SHIPHOOK_DEPLOY_TOKEN` | per-route Shiphook secret (mint below) |

Make the GHCR image package **public** so k3s can pull it
(`Settings → Packages → agentic-book-web → Change visibility`).

## One-time server setup (run on `blackpearl`)

1. **Clone agentic-book** (Shiphook `git pull`s this for the commit SHA):
   ```bash
   mkdir -p ~/agentic-book && git clone git@github.com:agentic-book-org/agentic-book.git ~/agentic-book
   ```

2. **Shiphook runScript** already lives in this repo at
   `scripts/agentic-book-shiphook-deploy.sh` — no copy needed. The server runs it
   via the absolute path in the route below.

3. **Add the route** to the server's Shiphook config
   (`~/staging/shiphook-server/shiphook.yaml`) under `apps:`:
   ```yaml
   - name: agentic-book
     host: shiphook.agentic-book.org
     path: /deploy/agentic-book
     repoPath: /home/s4il0r/agentic-book
     runScript: bash /home/s4il0r/staging/homelab-k3s/scripts/agentic-book-shiphook-deploy.sh
     runTimeoutMs: 1800000
     secret: <DEPLOY_TOKEN>
   ```

4. **Mint the deploy secret** (same value in `secret:` above AND the GitHub
   secret `SHIPHOOK_DEPLOY_TOKEN`). Generate a strong token:
   ```bash
   tr -d -c 'a-zA-Z0-9' </dev/urandom | head -c 32 | sed 's/$/\\\n/' > ~/.shiphook.agentic-book.secret
   cat ~/.shiphook.agentic-book.secret          # use this value...
   gh secret set SHIPHOOK_DEPLOY_TOKEN --repo agentic-book-org/agentic-book -R agentic-book-org/agentic-book < ~/.shiphook.agentic-book.secret
   # ...and paste it into the route's `secret:` field above.
   ```
   Alternatively, omit `secret:` from the route and let Shiphook auto-generate
   one into `~/agentic-book/.shiphook/…<hash>.secret`; `cat` it and set
   `SHIPHOOK_DEPLOY_TOKEN` from it.

5. **Apply the web Service** (NodePort 30608) once:
   ```bash
   kubectl apply -f k8s/agentic-book/agentic-book-web.yaml   # or via watchtower
   ```
   Verify the `selector` matches the live `agentic-book-web` Deployment pod labels.

6. **Edge routing**:
   - li-httpd: merge `k8s/edge/agentic-book-shiphook.httpd.toml` into `homelab.httpd.toml`,
     then `sudo bash scripts/edge-lis-apply.sh --install-systemd`.
   - nginx (HTTPS for agentic-book.org): `cp k8s/edge/nginx-agentic-book-web.conf /etc/nginx/conf.d/`
     and `nginx -t && systemctl reload nginx` (the `agentic-book.org` LE cert is shared
     with supabase.agentic-book.org).

7. **Watchdog**: the `agentic-book` row was added to
   `k8s/monitoring/cluster-watchdog/services.conf`; deploy it via
   `sudo bash scripts/deploy-cluster-watchdog.sh` (or re-copy services.conf + restart the
   timer). It probes `127.0.0.1:30608/api/books` and restarts pods on failure.

## Verify

```bash
# from blackpearl
kubectl -n agentic-book-supabase get deploy agentic-book-web
kubectl -n agentic-book-supabase rollout status deployment/agentic-book-web --timeout=180s
# Shiphook self-test (after first deploy, so the route+secret exist)
TOKEN="$(... the shared deploy token ...)"
curl -sS -m 30 -X POST "https://shiphook.agentic-book.org/deploy/agentic-book?format=json" \
  -H "X-Shiphook-Secret: $TOKEN" -d '{}' | tail -3
```
