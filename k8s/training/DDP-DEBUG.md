# PyTorch DDP smoke — debugging notes

## Prerequisites

1. Desktop burst mode: `./scripts/desktop-gpu-burst-on.sh`
2. Engine UFW (run on **engine** as root): `./scripts/homelab-engine-ddp-ufw.sh`
3. Desktop/WSL must allow **inbound TCP 1024–65535** from `192.168.10.0/24` (NCCL uses ephemeral ports). Engine→desktop connections fail with `Software caused connection abort` until this is open.

## Run

```bash
./scripts/k8s-training-smoke.sh ddp
```

Or manually:

```bash
kubectl apply -f k8s/training/pytorch-ddp-smoke.yaml
kubectl delete job pytorch-ddp-master pytorch-ddp-worker -n training --ignore-not-found
kubectl apply -f k8s/training/pytorch-ddp-master-job.yaml
kubectl -n training wait --for=condition=ready pod -l ddp-role=master --timeout=120s
kubectl apply -f k8s/training/pytorch-ddp-worker-job.yaml
kubectl -n training wait --for=condition=complete job/pytorch-ddp-master job/pytorch-ddp-worker --timeout=600s
```

## Root causes found (2026-05-31)

| Issue | Fix |
|-------|-----|
| Hardcoded `pytorch-ddp-master.training.svc.cluster.local` | Use `env://` init + fixed engine IP / pod IP |
| No RBAC to list rank-0 pod | `Role` + `RoleBinding` in `pytorch-ddp-smoke.yaml` |
| Indexed job scheduling race | Split **master** (engine) and **worker** (desktop) jobs |
| Pod CIDR unreachable WSL↔engine | `hostNetwork: true` + engine `ufw` allow 29500 and 1024–65535 |
| NCCL wrong interface on engine | `NCCL_SOCKET_IFNAME=eno1,eth0` |
| Worker starts before master listens | `initContainer` `wait-master` on worker job |

## Verify

```bash
kubectl -n training logs job/pytorch-ddp-master --prefix
kubectl -n training logs job/pytorch-ddp-worker -c trainer --prefix
# Success: host=... all_reduce=1 expected=1 and "rank N ok"
```
