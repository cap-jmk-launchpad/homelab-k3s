# Obsevia chat staging on homelab k3s

Deploy **chatbot-frontend** staging to **blackpearl** (local k3s). Same env contract as VPS3 Docker staging (`docker-compose.staging.yml` / `.env.staging.example` in [chatbot-frontend](https://github.com/obsevia-compliance/chatbot-frontend)).

**Does not change** production VPS3 nginx (`chat.obsevia.com`) or Docker HA on `217.154.167.236`.

## Cluster

| Item | Value |
|------|--------|
| Control plane | **blackpearl** — API `https://192.168.10.33:6443` (SSH often `192.168.10.41`) |
| Edge | **li-httpd** on `192.168.10.33:80` → loopback NodePorts |
| Workstation kubeconfig | `scp -i homelab s4il0r@192.168.10.41:~/.kube/config $env:USERPROFILE\.kube\config-homelab` |
| Apply | `$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-homelab"` |

## Manifests

| Path | Purpose |
|------|---------|
| [`k8s/staging/chat-frontend/`](../k8s/staging/chat-frontend/) | Namespace, Deployment (2 replicas), Services, ConfigMap |
| [`k8s/staging/chat-frontend/secret.example.yaml`](../k8s/staging/chat-frontend/secret.example.yaml) | Copy → `secret.yaml` (gitignored) |
| [`k8s/edge/chat-staging.httpd.toml`](../k8s/edge/chat-staging.httpd.toml) | Edge snippet (merged into `homelab.httpd.toml`) |

| Resource | Value |
|----------|--------|
| Namespace | `obsevia-chat-staging` |
| NodePort | **30581** |
| Image | `docker.io/library/obsevia-frontend-staging:latest` (`imagePullPolicy: Never`, sideload) |
| Schedule | `nodeSelector: kubernetes.io/hostname: blackpearl` |
| UI | `NEXT_PUBLIC_DEPLOY_ENV=staging` → amber **STAGING** banner; design-system `ObseviaLogo` in app image |

## URLs (homelab)

| URL | When |
|-----|------|
| **http://chat.homelab.lan** | LAN DNS (`*.homelab.lan` → `192.168.10.33`) or [hosts file](homelab-lan-dns.md#option-c--windows-hosts-file-quick-fix) |
| **http://chat.obsevia.d3bu7.com** | Add **local** override: hosts / Fritz DNS → `192.168.10.33` (see below) |
| **http://192.168.10.33:30581/login** | NodePort debug (no edge) |
| `kubectl port-forward -n obsevia-chat-staging svc/obsevia-chat-frontend 3000:3000` | Workstation-only |

### DNS: `chat.obsevia.d3bu7.com`

Public DNS for this name may point at **VPS3** (`217.154.167.236`) for Docker staging ([obsevia-kubernetes staging-chat](https://github.com/obsevia-compliance/obsevia-kubernetes/blob/main/docs/staging-chat.md)). To use **homelab** instead on your LAN:

1. **Split-horizon / Fritz local DNS** — A record `chat.obsevia.d3bu7.com` → `192.168.10.33` on the LAN only, or  
2. **Windows hosts** (admin): `192.168.10.33 chat.obsevia.d3bu7.com`

Homelab edge is **HTTP :80** for this hostname; HTTPS on VPS3 is separate.

## One-time setup

```powershell
# 1. Secret from chatbot-frontend staging env
Copy-Item C:\Users\Julian\Documents\Programming\Obsevia\obsevia-compliance\chatbot-frontend\.env.staging `
  C:\Users\Julian\Documents\Programming\beelink-cleanup\k8s\staging\chat-frontend\secret.yaml
# Or: copy secret.example.yaml and fill keys

# 2. Build, import image, apply (from beelink-cleanup)
cd C:\Users\Julian\Documents\Programming\beelink-cleanup
.\scripts\deploy-chat-staging-homelab.ps1
```

On **blackpearl** after edge TOML changes:

```bash
cd ~/staging/beelink-cleanup
bash scripts/edge-lis-validate.sh
sudo bash scripts/edge-lis-apply.sh
# If using homelab CoreDNS:
kubectl apply -f k8s/dns/coredns-configmap.yaml
kubectl -n homelab-dns rollout restart daemonset/homelab-lan-coredns
```

## kubectl apply (manual)

```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-homelab"
kubectl apply -f k8s/staging/chat-frontend/secret.yaml
kubectl apply -k k8s/staging/chat-frontend/
kubectl -n obsevia-chat-staging rollout status deployment/obsevia-chat-frontend --timeout=180s
kubectl -n obsevia-chat-staging get pods,svc
```

## Build args (must match runtime secret)

From `.env.staging` / `docker-compose.staging.yml`:

- `NEXT_PUBLIC_SITE_URL` — default `https://chat.obsevia.d3bu7.com`
- `NEXT_PUBLIC_DEPLOY_ENV=staging`
- `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_API_URL`
- `SUPABASE_SERVICE_ROLE_KEY` (build + runtime)

Rebuild and re-import the image after changing any `NEXT_PUBLIC_*` build arg.

## Verify

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: chat.homelab.lan' http://192.168.10.33/login
curl -sS -o /dev/null -w '%{http_code}\n' http://192.168.10.33:30581/login
```

Browser: open **http://chat.homelab.lan/login** — expect STAGING banner when `NEXT_PUBLIC_DEPLOY_ENV=staging` was baked in.

## Related

- VPS3 Docker staging: [obsevia-kubernetes/docs/staging-chat.md](https://github.com/obsevia-compliance/obsevia-kubernetes/blob/main/docs/staging-chat.md)
- DUCA homelab pattern: [Obsevia DUCA-DEMO `k8s/`](https://github.com/obsevia-compliance/DUCAH/tree/main/k8s)
- Homelab edge: [edge-ingress.md](edge-ingress.md), [homelab-lan-dns.md](homelab-lan-dns.md)
