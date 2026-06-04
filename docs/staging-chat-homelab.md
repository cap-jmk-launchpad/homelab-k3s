# Obsevia chat staging on homelab k3s

Deploy **chatbot-frontend** staging to the homelab **k3s** cluster. Same env contract as VPS3 Docker staging (`docker-compose.staging.yml` / `.env.staging.example` in [chatbot-frontend](https://github.com/obsevia-compliance/chatbot-frontend)).

**Does not change** production VPS3 nginx (`chat.obsevia.com`) or Docker HA on `217.154.167.236`.

## Cluster nodes

| Host | IP (k3s / SSH) | Role |
|------|----------------|------|
| **blackpearl** | `192.168.10.33` (node), `192.168.10.41` (SSH) | k3s **server**, **li-httpd** edge `:80` / LAN DNS |
| **engine** | `192.168.10.32` | k3s **agent**, GPU, RAM-heavy workloads (GitLab, Prometheus, …) |

**Recommended schedule:** **`engine`** — frees control-plane RAM; same pattern as [gitlab-homelab.md](gitlab-homelab.md) and [scripts/homelab-move-workloads-to-engine.sh](../scripts/homelab-move-workloads-to-engine.sh).

Edge and DNS still target **blackpearl** `192.168.10.33`; NodePort **30581** is reachable on the edge host loopback even when pods run on `engine`.

| Item | Value |
|------|--------|
| API | `https://192.168.10.41:6443` |
| Workstation kubeconfig | `scp -i homelab s4il0r@192.168.10.41:~/.kube/config $env:USERPROFILE\.kube\config-homelab` |
| Apply | `$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-homelab"` |

## Manifests

| Path | Purpose |
|------|---------|
| [`k8s/staging/chat-frontend/`](../k8s/staging/chat-frontend/) | Base: namespace, Deployment, Services, ConfigMap |
| [`k8s/staging/chat-frontend/overlays/engine/`](../k8s/staging/chat-frontend/overlays/engine/) | **Default** — `nodeSelector: engine` |
| [`k8s/staging/chat-frontend/overlays/blackpearl/`](../k8s/staging/chat-frontend/overlays/blackpearl/) | Legacy pin to control plane |
| [`k8s/staging/chat-frontend/secret.example.yaml`](../k8s/staging/chat-frontend/secret.example.yaml) | Copy → `secret.yaml` (gitignored) |
| [`k8s/edge/chat-staging.httpd.toml`](../k8s/edge/chat-staging.httpd.toml) | Edge snippet (merged into `homelab.httpd.toml`) |

| Resource | Value |
|----------|--------|
| Namespace | `obsevia-chat-staging` |
| NodePort | **30581** (all nodes; edge uses `127.0.0.1:30581` on blackpearl) |
| Image | `docker.io/library/obsevia-frontend-staging:latest` (`imagePullPolicy: Never`, sideload on **schedule node**) |
| Schedule | `kubernetes.io/hostname: engine` (default) |
| UI | `NEXT_PUBLIC_DEPLOY_ENV=staging` → amber **STAGING** banner |

## URLs (homelab)

| URL | When |
|-----|------|
| **http://chat.homelab.lan** | LAN DNS (`*.homelab.lan` → `192.168.10.33`) or [hosts file](homelab-lan-dns.md#option-c--windows-hosts-file-quick-fix) |
| **http://chat.obsevia.d3bu7.com** | Local override: hosts / Fritz DNS → **`192.168.10.33`** (edge, not engine) |
| **http://192.168.10.33:30581/login** | NodePort via blackpearl / edge node |
| **http://192.168.10.32:30581/login** | NodePort direct on engine (pod locality debug) |
| `kubectl port-forward -n obsevia-chat-staging svc/obsevia-chat-frontend 3000:3000` | Workstation-only |

### DNS: `chat.obsevia.d3bu7.com`

Public DNS may point at **VPS3** for Docker staging. For **homelab** on your LAN:

1. **Fritz local DNS** — `chat.obsevia.d3bu7.com` → `192.168.10.33`, or  
2. **Windows hosts**: `192.168.10.33 chat.obsevia.d3bu7.com`

Homelab edge is **HTTP :80** on blackpearl; do not point this hostname at engine unless you run a separate reverse proxy there.

### Edge routing (Caddy on :80)

**Caddy** binds **:80** on blackpearl for WAN + LAN hostnames. **li-httpd** homelab units cannot take :80 while Caddy is active, so chat hostnames are routed in [k8s/edge/Caddyfile](../k8s/edge/Caddyfile) → `127.0.0.1:30581` (not via a live li-httpd listener).

`edge-lis-apply.sh` still merges [homelab.httpd.toml](../k8s/edge/homelab.httpd.toml) for when li-httpd runs, but **flatten** on the full multi-site profile can fail (duplicate `listen` / site keys across merged TOML). Prefer **Caddy** for chat until li-httpd multi-site flatten is fixed.

After changing the Caddyfile:

```bash
cd ~/staging/beelink-cleanup   # or homelab-k3s mirror on blackpearl
sudo bash scripts/edge-caddy-apply.sh
```

## Deploy (engine, default)

```powershell
cd C:\Users\Julian\Documents\Programming\beelink-cleanup

# Secret from chatbot-frontend (one-time)
Copy-Item C:\Users\Julian\Documents\Programming\Obsevia\obsevia-compliance\chatbot-frontend\.env.staging `
  k8s\staging\chat-frontend\secret.yaml -ErrorAction SilentlyContinue

.\scripts\deploy-chat-staging-homelab.ps1
# Same as: .\scripts\deploy-chat-staging-homelab.ps1 -Target engine

# Legacy control-plane schedule + import:
.\scripts\deploy-chat-staging-homelab.ps1 -Target blackpearl
```

Image import runs on the **target node** (`engine` hostname or `192.168.10.41` for blackpearl) because `imagePullPolicy: Never`.

On **blackpearl** after edge changes (chat URLs use **Caddy**, not li-httpd :80):

```bash
cd ~/staging/beelink-cleanup
sudo bash scripts/edge-caddy-apply.sh
# Optional: validate merged li-httpd TOML only (flatten may still fail on blackpearl)
bash scripts/edge-lis-validate.sh
kubectl apply -f k8s/dns/coredns-configmap.yaml   # if using homelab CoreDNS
kubectl -n homelab-dns rollout restart daemonset/homelab-lan-coredns
```

## kubectl apply (manual)

```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-homelab"
kubectl apply -f k8s/staging/chat-frontend/secret.yaml
kubectl apply -k k8s/staging/chat-frontend/overlays/engine/
kubectl -n obsevia-chat-staging rollout status deployment/obsevia-chat-frontend --timeout=180s
kubectl -n obsevia-chat-staging get pods -o wide
```

## Build args (must match runtime secret)

From `.env.staging` / `docker-compose.staging.yml`:

- `NEXT_PUBLIC_SITE_URL` — default `https://chat.obsevia.d3bu7.com`
- `NEXT_PUBLIC_DEPLOY_ENV=staging`
- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_API_URL`
- `SUPABASE_SERVICE_ROLE_KEY` (build + runtime)

Rebuild and re-import the image after changing any `NEXT_PUBLIC_*` build arg.

**Image runtime:** the runner stage must keep `next` after build (see `chatbot-frontend` `Dockerfile` — copy `node_modules` from the builder stage, not `npm prune` on deps alone).

## Verify

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: chat.homelab.lan' http://192.168.10.33/login
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: chat.obsevia.d3bu7.com' http://192.168.10.33/login
curl -sS -o /dev/null -w '%{http_code}\n' http://192.168.10.33:30581/login
curl -sS -o /dev/null -w '%{http_code}\n' http://192.168.10.32:30581/login
```

Expect **307** (or **302**) on `/login` via Caddy and NodePort when the staging deployment is healthy.

Browser: **http://chat.homelab.lan/login** — STAGING banner when baked in at build time.

## engine vs blackpearl

| | **engine** (recommended) | **blackpearl** |
|--|-------------------------|----------------|
| Role | Worker, more RAM/GPU | Control plane + edge |
| Why | Same as GitLab/DT/Prometheus placement; avoids starving API/etcd adjacent workloads | Only if engine down or quick local debug |
| Image import | `ssh s4il0r@engine` | `ssh s4il0r@192.168.10.41` |
| Edge URL | Unchanged (`192.168.10.33`) | Unchanged |

## Related

- VPS3 Docker staging: [obsevia-kubernetes/docs/staging-chat.md](https://github.com/obsevia-compliance/obsevia-kubernetes/blob/main/docs/staging-chat.md)
- Homelab edge: [edge-ingress.md](edge-ingress.md), [homelab-lan-dns.md](homelab-lan-dns.md)
- SSH: [homelab-ssh-keys.md](homelab-ssh-keys.md)
