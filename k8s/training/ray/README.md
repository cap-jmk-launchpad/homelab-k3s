# Ray cluster on homelab k3s

[KubeRay](https://docs.ray.io/en/latest/cluster/kubernetes/index.html) runs a Ray head plus GPU and CPU worker groups in the `training` namespace.

## Install (once)

```bash
./scripts/k8s-training-ray-install.sh
```

## Deploy

```bash
kubectl apply -f k8s/training/ray/raycluster.yaml
kubectl -n training get raycluster,pods -l ray.io/cluster=homelab-ray
```

## Use

Port-forward the dashboard:

```bash
# KubeRay creates homelab-ray-head-svc automatically
kubectl -n training port-forward svc/homelab-ray-head-svc 8265:8265
```

Open `http://127.0.0.1:8265`.

Submit a job from your laptop (after `pip install ray`):

```python
import ray

ray.init("ray://127.0.0.1:10001")  # while port-forwarding client port:
# kubectl -n training port-forward svc/homelab-ray-head-svc 10001:10001

@ray.remote(num_gpus=1)
def gpu_task(x):
    import torch
    return x, torch.cuda.get_device_name(0)

print(ray.get(gpu_task.remote(42)))
```

Or use `ray job submit` against the dashboard address.

## Worker groups

| Group | Nodes | Resources |
|-------|-------|-----------|
| `gpu` | engine, desktop (`gpu=nvidia`) | 1 GPU, 4 CPU, 8Gi |
| `cpu-pi` | deck, anch0r | 1 CPU, 512Mi |

Scale GPU workers down when desktop is in use:

```bash
kubectl -n training patch raycluster homelab-ray --type=json \
  -p='[{"op":"replace","path":"/spec/workerGroupSpecs/0/replicas","value":1}]'
```
