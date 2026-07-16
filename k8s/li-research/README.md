# li-research � homelab k8s

Warm index + research gateway on **engine NVMe** (`nvme0n1`, label `homelab-nvme` @ `/srv/homelab/nvme`).

| Disk | Mount | Use |
|------|-------|-----|
| sdb | `/var/lib/lip-registry`, `/srv/homelab/external` | **LiP only** |
| sdc | `/srv/homelab/intenso-research` | spare USB bulk (not warm-index) |
| nvme | `/srv/homelab/nvme` | **li-research warm-index + runs** |

## Gateway (NodePort 30487)

| Resource | File |
|----------|------|
| Service | `service.yaml` — NodePort **30487** (30486 is GitLab Pages) |
| Image deploy | `deployment.yaml` — `ghcr.io/klaut-pro/klaut-research-gateway:scaffold` |
| Bootstrap (no image) | `bootstrap-deployment.yaml` — clones Python branch + `uv run` |
| Secrets example | `secret.example.yaml` |

Edge (`homelab.httpd.toml`): `research.klaut.pro` → `127.0.0.1:30487`.

Runs persist under PVC subpath `runs` → container `/data/runs` (`RESEARCH_RUNS_PATH`).

### Apply (bootstrap first)

```bash
kubectl apply -f k8s/li-research/namespace.yaml
kubectl apply -f k8s/li-research/storage-class.yaml
kubectl apply -f k8s/li-research/pv-warm-index.yaml
kubectl apply -f k8s/li-research/pvc-warm-index.yaml
# create secret from secret.example.yaml (edit values) OR kubectl create secret ...
kubectl apply -f k8s/li-research/bootstrap-deployment.yaml
kubectl apply -f k8s/li-research/service.yaml
kubectl -n li-research rollout status deployment/klaut-research-gateway
curl -sS http://127.0.0.1:30487/health | jq .
```

On engine, ensure dirs exist for subPaths:

```bash
sudo mkdir -p /srv/homelab/nvme/li-research/warm-index/{runs,reports}
```

## Storage apply

```bash
kubectl apply -f k8s/li-research/namespace.yaml
kubectl apply -f k8s/li-research/storage-class.yaml
kubectl apply -f k8s/li-research/pv-warm-index.yaml
kubectl apply -f k8s/li-research/pvc-warm-index.yaml
```

Host path: `/srv/homelab/nvme/li-research/warm-index` (250 Gi PV, ~915 Gi NVMe).
