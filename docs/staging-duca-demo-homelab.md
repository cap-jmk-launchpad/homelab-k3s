# DUCAH (DUCA-DEMO) staging on homelab k3s

Deploy the **DUCAH compliance demo** (`obsevia-compliance/DUCAH`, local `DUCA-DEMO`) to homelab k3s. This is **not** the freemium chat product (`chat.obsevia.com` / `chatbot-frontend`).

## Cluster nodes

| Host | IP | Role |
|------|-----|------|
| **blackpearl** | `192.168.10.33` (node), `192.168.10.41` (SSH) | k3s server, **li-httpd** edge `:80` |
| **engine** | `192.168.10.32` | k3s agent — **schedule DUCAH pods here** |

| Item | Value |
|------|--------|
| Namespace | `obsevia-ducah-staging` |
| NodePort | **30583** |
| Image | `docker.io/library/obsevia-duca-demo-staging:latest` (`imagePullPolicy: Never`) |
| Replicas | 2 on `engine` |

## Manifests

| Path | Purpose |
|------|---------|
| [`k8s/staging/duca-demo/base/`](../k8s/staging/duca-demo/base/) | Namespace, Deployment, Services, ConfigMap |
| [`k8s/staging/duca-demo/overlays/engine/`](../k8s/staging/duca-demo/overlays/engine/) | Default schedule on `engine` |
| [`k8s/staging/duca-demo/secret.example.yaml`](../k8s/staging/duca-demo/secret.example.yaml) | Copy → `secret.yaml` (gitignored) |
| [`k8s/edge/homelab.httpd.toml`](../k8s/edge/homelab.httpd.toml) | Edge routes → `127.0.0.1:30583` |

## URLs (homelab)

| URL | When |
|-----|------|
| **http://ducah.homelab.lan** | LAN DNS (`*.homelab.lan` → `192.168.10.33`) |
| **http://ducah.obsevia.d3bu7.com** | Local hosts/Fritz DNS → **`192.168.10.33`** (parallel to chat staging) |
| **http://192.168.10.33:30583/login** | NodePort via edge |
| **http://192.168.10.32:30583/login** | NodePort on engine (debug) |

`NEXT_PUBLIC_APP_URL` / `NEXT_PUBLIC_SUPABASE_URL` in the staging ConfigMap: **`http://ducah.homelab.lan`** (Next.js proxies `/auth/v1` to majico Kong).

## Deploy

```powershell
cd C:\Users\Julian\Documents\Programming\beelink-cleanup
.\scripts\deploy-duca-demo-staging-homelab.ps1
```

On **blackpearl** after edge TOML changes:

```bash
cd ~/staging/beelink-cleanup
bash scripts/homelab-edge-policy-check.sh
bash scripts/edge-lis-validate.sh
sudo bash scripts/edge-lis-apply.sh
```

## Verify

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: ducah.homelab.lan' http://192.168.10.33/login
curl -sS -o /dev/null -w '%{http_code}\n' http://192.168.10.33:30583/login
```

Expect **200** on `/login` when healthy.

## Production (separate)

| Product | URL | Host |
|---------|-----|------|
| **DUCAH demo** | https://ducah.obsevia.com | VPS1 `82.165.195.105` |
| **Chat (freemium)** | https://chat.obsevia.com | VPS3 — **do not modify** for DUCAH |

See [obsevia-kubernetes/docs/dns-domains.md](https://github.com/obsevia-compliance/obsevia-kubernetes/blob/main/docs/dns-domains.md) and `DUCA-DEMO/scripts/deploy-staging.ps1`.

## Related

- Chat staging (different app): [staging-chat-homelab.md](staging-chat-homelab.md)
- Legacy `high-fi-demos` namespace (port 30580) — superseded by `obsevia-ducah-staging` on 30583
