# Agent swarm on homelab k3s

Run the **li-cursor-agents** control plane on your cluster:

| Component | What it is | This layout |
|-----------|------------|-------------|
| **Database** | Supabase (Postgres + PostgREST) | **On the host** via Docker (`npm run db:ensure`) — same as Mac/systemd |
| **Dashboard** | UI + API (`serve-dashboard`) | Kubernetes `Deployment` + NodePort **30477** |
| **Agent swarm** | `async-swarm` lanes + SDK slots | Separate `Deployment` (does not block the HTTP server) |

Source repo: `li/li-cursor-agents` (sibling of `benchmarks`, `lic`, `li-local-ci`).

Homelab manifests live here; application code stays in the **li** monorepo checkout on the node.

### Raspberry Pi **deck**

Use the **deck** overlay (arm64, lower memory, DB still on blackpearl):

- Guide: [overlays/deck/README.md](./overlays/deck/README.md)
- Prepare Pi: `./scripts/k8s-agent-swarm-prepare-deck.sh`
- Deploy: `./scripts/k8s-agent-swarm-apply-deck.sh`
- UI: `http://192.168.10.26:30477/`

## Prerequisites

1. **k3s cluster** with `kubectl` working (see [docs/homelab-monitoring.md](../../docs/homelab-monitoring.md) — control plane on **blackpearl** `192.168.10.41`).
2. **Li checkout** on the node you schedule pods on (default `blackpearl`), e.g.  
   `/home/s4il0r/Documents/Cursor/li-langverse`
3. **Docker on that node** for Supabase (control plane store).
4. **Secrets**: `CURSOR_API_KEY`, `GH_TOKEN`, Supabase keys (from `npm run db:ensure` in `li-cursor-agents`).

### kubectl from Windows (your PC)

`kubectl` on Windows currently has **no context**. Copy kubeconfig from blackpearl:

```bash
# On blackpearl
sudo cat /etc/rancher/k3s/k3s.yaml
```

Save as `%USERPROFILE%\.kube\config`, replace `127.0.0.1` with `192.168.10.41`, then:

```powershell
kubectl config use-context default
kubectl get nodes
```

## 1. Supabase (database) on the host

On the **same machine** as the pod `hostPath` (default blackpearl), in `li-cursor-agents`:

```bash
cd /path/to/li-langverse/li-cursor-agents
cp .env.example .env   # add CURSOR_API_KEY
npm run setup
npm run db:ensure      # starts Docker Supabase, writes .env.supabase
```

Note `SUPABASE_URL` and keys from `.env.supabase`. API is usually `http://127.0.0.1:54321` on the host; pods use the host LAN IP (see `configmap.yaml`).

**Stop systemd duplicates** on that host if you used Mac-style units before:

```bash
systemctl --user disable --now li-agents-dashboard.service li-agents-async-swarm.service 2>/dev/null || true
```

## 2. Configure paths and Supabase URL

Edit [configmap.yaml](./configmap.yaml):

- `LI_HOST_ROOT` / deployment `hostPath` — must match the real path on the node.
- `SUPABASE_URL` — `http://<node-lan-ip>:54321` (not `127.0.0.1` from inside pods).
- `nodeSelector.kubernetes.io/hostname` in both deployments if you use **engine** or **desktop** instead of blackpearl.

## 3. Create the Kubernetes secret

From a machine with `kubectl` and your `.env` + `.env.supabase`:

```bash
cd beelink-cleanup
./scripts/k8s-agent-swarm-secret.sh /path/to/li-cursor-agents/.env
```

Or merge manually from `.env` and `.env.supabase` (see [secret.example.yaml](./secret.example.yaml)).

## 4. Deploy

```bash
cd beelink-cleanup
./scripts/k8s-agent-swarm-apply.sh
```

Or:

```bash
kubectl apply -k k8s/agent-swarm/
kubectl -n agent-swarm create secret generic agent-swarm-secrets ...  # if not done yet
```

## 5. Verify

```bash
kubectl -n agent-swarm get pods,svc
kubectl -n agent-swarm logs -f deploy/agents-dashboard
curl -sf http://192.168.10.41:30477/api/health
```

**Dashboard URL:** `http://<node-ip>:30477/` (NodePort **30477**).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  k3s node (e.g. blackpearl)                                 │
│  ┌─────────────────────┐   hostPath: li-langverse checkout  │
│  │ Pod: dashboard      │──────────────────────────────────┐ │
│  │ NodePort :30477     │                                  │ │
│  └──────────┬──────────┘                                  │ │
│  ┌──────────┴──────────┐                                  │ │
│  │ Pod: async-swarm    │──────────────────────────────────┘ │
│  └──────────┬──────────┘                                    │
│             │ SUPABASE_URL → host LAN :54321                │
│  ┌──────────▼──────────┐                                    │
│  │ Docker: supabase     │  npm run db:ensure (host)         │
│  │ Postgres + REST      │                                   │
│  └─────────────────────┘                                    │
└─────────────────────────────────────────────────────────────┘
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `CrashLoopBackOff` on dashboard | `kubectl logs` — often `npm ci` or missing hostPath; check path on node |
| `/api/health` 503 / DB off | Wrong `SUPABASE_URL` from pod network; fix ConfigMap; ensure Docker Supabase on host |
| Site loads but swarm idle | Check `agents-async-swarm` logs; `CURSOR_API_KEY` in secret |
| Port in use on host | Old systemd dashboard still running — disable user units |
| Windows kubectl fails | Install context (above); cluster API is on blackpearl, not localhost:8080 |

## Related docs

- `li/li-cursor-agents/docs/ecosystem/swarm-architecture.md`
- `li/li-cursor-agents/docs/ecosystem/dashboard-lan-access.md`
- [k8s/monitoring/](../monitoring/) — Grafana NodePort `30300`
