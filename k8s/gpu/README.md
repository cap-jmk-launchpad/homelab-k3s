# Homelab GPU (k3s)

NVIDIA GPU scheduling and metrics for **engine** (`192.168.10.32`) and **desktop** (`192.168.10.31`, WSL2 agent).

## Prerequisites (each GPU node)

1. Host driver: `nvidia-smi` works on the node (not inside a default container).
2. [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) installed.
3. k3s agent containerd imports NVIDIA runtime (toolkit writes `/etc/containerd/conf.d/99-nvidia.toml`; k3s already imports that path).
4. Restart agent: `sudo systemctl restart k3s-agent` (or `k3s` on server).
5. Label node: `kubectl label node <name> gpu=nvidia --overwrite` and optionally `workload=training`.

### Engine (Debian/k3s agent)

```bash
# On engine — see homelab SSH key from repo root
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg --yes
echo 'deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/amd64 /' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=containerd --config /var/lib/rancher/k3s/agent/etc/containerd/config.toml
sudo systemctl restart k3s-agent
```

### Desktop (Ubuntu WSL2 + k3s agent)

Blockers if `nvidia-smi` fails in WSL:

- Install current **Windows** NVIDIA driver with WSL support.
- Use WSL2 (not WSL1); Ubuntu 22.04+ recommended.
- From Windows PC or jump via blackpearl: `ssh -p 2222 s4il0r@192.168.10.31` (key must be authorized on desktop).

When `nvidia-smi` works in WSL, repeat the toolkit + `k3s-agent` restart steps above, then:

```bash
kubectl label node desktop gpu=nvidia workload=training --overwrite
```

WSL often needs toolkit config:

```bash
sudo nvidia-ctk config --set nvidia-container-runtime.no-cgroups=true
```

## Kubernetes manifests

```bash
kubectl apply -f nvidia-runtimeclass.yaml
kubectl apply -f nvidia-device-plugin.yaml
kubectl apply -f ../monitoring/dcgm-exporter.yaml
```

Verify:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.capacity.nvidia\\.com/gpu
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds -o wide
kubectl get pods -n monitoring -l app=dcgm-exporter -o wide
```

Per-node DCGM metric count (from blackpearl):

```bash
for p in $(kubectl get pods -n monitoring -l app=dcgm-exporter -o jsonpath='{.items[*].metadata.name}'); do
  echo -n "$p: "
  kubectl exec -n monitoring "$p" -- wget -qO- http://127.0.0.1:9400/metrics | grep -c DCGM_FI || echo 0
done
```
