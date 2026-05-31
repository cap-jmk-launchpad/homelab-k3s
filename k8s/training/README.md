# Distributed compute on homelab k3s

Run parallel and multi-node workloads on **engine** (training GPU), **desktop** (burst GPU), and **deck** / **anch0r** (CPU Pis).

Prerequisites:

```bash
kubectl apply -f k8s/gpu/nvidia-runtimeclass.yaml
kubectl apply -f k8s/gpu/nvidia-device-plugin.yaml
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.capacity.nvidia\\.com/gpu,LABELS:.metadata.labels.workload
```

## Quick smoke tests

From blackpearl (or any host with `kubectl`):

```bash
./scripts/k8s-training-smoke.sh          # single-GPU on engine
./scripts/k8s-training-smoke.sh ddp      # 2-GPU PyTorch DDP (engine + desktop)
./scripts/k8s-training-smoke.sh sweep    # 10-way indexed CPU sweep
```

Monitor in Grafana: `http://192.168.10.41:30300/d/homelab-cluster-resources/homelab-cluster-resources`

## Manifests

| File | Purpose |
|------|---------|
| [gpu-smoke-job.yaml](./gpu-smoke-job.yaml) | Single GPU sanity check on `workload=training` |
| [pytorch-ddp-smoke.yaml](./pytorch-ddp-smoke.yaml) | 2-node PyTorch DDP all-reduce across GPU nodes |
| [indexed-sweep-job.yaml](./indexed-sweep-job.yaml) | Parameter sweep template (Indexed Job, CPU) |
| [cpu-fanout-job.yaml](./cpu-fanout-job.yaml) | Parallel CPU tasks on deck + anch0r |
| [ray/](./ray/) | Optional Ray cluster (KubeRay) for general Python distributed compute |

## PyTorch DDP (multi-GPU)

Requires **two** nodes labeled `gpu=nvidia` (engine + desktop). Pods are spread with anti-affinity so each rank lands on a different host.

```bash
kubectl apply -f k8s/training/pytorch-ddp-smoke.yaml
kubectl -n training wait --for=condition=complete job/pytorch-ddp-smoke --timeout=600s
kubectl -n training logs job/pytorch-ddp-smoke --all-containers
```

Rank 0 prints the all-reduce sum when both GPUs participate. Adapt [pytorch-ddp-smoke.yaml](./pytorch-ddp-smoke.yaml) for real training: swap the ConfigMap script and image, keep the headless Service + Indexed Job pattern.

## Indexed parameter sweep

Each pod receives `JOB_COMPLETION_INDEX` (0 … N−1). Use it to pick hyperparameters or shard input data.

```bash
kubectl apply -f k8s/training/indexed-sweep-job.yaml
kubectl -n training wait --for=condition=complete job/param-sweep --timeout=300s
kubectl -n training logs job/param-sweep --prefix=true
```

## Ray cluster (optional)

For ad-hoc distributed Python (tuning, ETL, RL):

```bash
./scripts/k8s-training-ray-install.sh    # once: KubeRay operator via Helm
kubectl apply -f k8s/training/ray/raycluster.yaml
kubectl -n training port-forward svc/homelab-ray-head-svc 8265:8265
# Dashboard: http://127.0.0.1:8265
```

See [ray/README.md](./ray/README.md).

## Scheduling labels

| Label | Nodes | Use |
|-------|-------|-----|
| `workload=training` | engine | Dedicated GPU training |
| `workload=burst` | desktop | GPU when daily driver is idle |
| `gpu=nvidia` | engine, desktop | Request `nvidia.com/gpu: 1` |

Docs: [engine-k3s-worker.md](../../docs/engine-k3s-worker.md), [desktop-k3s-worker.md](../../docs/desktop-k3s-worker.md), [k8s/gpu/README.md](../gpu/README.md).
