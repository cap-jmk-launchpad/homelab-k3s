# GPU workers (optional)

Dedicated **NVIDIA** nodes can join the cluster as k3s agents and run GPU workloads via the [NVIDIA device plugin](https://github.com/NVIDIA/k8s-device-plugin).

Placeholders: `<node-name>`, `<control-plane-host>`, `<lan-ip>`, `<admin-user>`.

## Prerequisites

- NVIDIA driver installed on the GPU host (verify with `nvidia-smi`).
- Worker joined per [k3s-workers.md](k3s-workers.md).
- Control plane has `kubectl` access.

## Label the GPU node

From the control plane:

```bash
kubectl label node <node-name> \
  workload=training gpu=nvidia machine=<node-name> --overwrite
```

Adjust label keys to match your scheduling policy.

## Install NVIDIA device plugin

```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.0/deployments/static/nvidia-device-plugin.yml
```

Verify:

```bash
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
kubectl describe node <node-name> | grep -A5 nvidia.com/gpu
```

## Smoke test job

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: training
---
apiVersion: batch/v1
kind: Job
metadata:
  name: gpu-smoke
  namespace: training
spec:
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      nodeSelector:
        workload: training
        gpu: nvidia
      containers:
        - name: nvidia-smi
          image: nvidia/cuda:12.2.0-base-ubuntu22.04
          command: ["nvidia-smi"]
          resources:
            limits:
              nvidia.com/gpu: 1
```

```bash
kubectl apply -f gpu-smoke-job.yaml
kubectl logs -n training job/gpu-smoke
```

## Scheduling production workloads

Request GPUs in pod spec:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
nodeSelector:
  workload: training
  gpu: nvidia
```

Optional **taints** on GPU nodes (`dedicated=training:NoSchedule`) prevent generic pods from landing there; add matching tolerations on training jobs only.

## Notes

- Keep GPU drivers and k3s agent versions maintained separately; reboot after driver upgrades.
- WSL2 GPU passthrough is possible but more fragile than bare-metal Linux — prefer a dedicated GPU box for training.
