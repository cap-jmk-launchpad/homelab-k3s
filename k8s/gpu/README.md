# Homelab GPU (k3s)

NVIDIA GPU scheduling and metrics for **engine** (`192.168.10.32`) and **desktop** (`192.168.10.31`, WSL2 agent).

## Prerequisites (each GPU node)

1. Host driver: `nvidia-smi` works on the node (not inside a default container).
2. [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) installed.
3. k3s agent containerd imports NVIDIA runtime (toolkit writes `/etc/containerd/conf.d/99-nvidia.toml`; k3s v1.35+ also needs a copy in `config-v3.toml.d` — see desktop).
4. Restart agent: `sudo systemctl restart k3s-agent` (or `k3s` on server).
5. Label node: `kubectl label node <name> gpu=nvidia --overwrite` and optionally `workload=training` or `workload=burst`.

### Engine (Debian/k3s agent)

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg --yes
echo 'deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/amd64 /' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=containerd --config /var/lib/rancher/k3s/agent/etc/containerd/config.toml
sudo systemctl restart k3s-agent
```

After restart, if pods fail with missing CNI plugins, run [engine-cni-opt-bin.sh](engine-cni-opt-bin.sh) on engine.

### Desktop (Ubuntu 24.04 WSL2 + k3s agent)

One-shot in WSL (see [desktop-wsl-setup.sh](desktop-wsl-setup.sh)):

```bash
bash k8s/gpu/desktop-wsl-setup.sh
kubectl label node desktop gpu=nvidia --overwrite   # from blackpearl; keeps workload=burst
```

WSL specifics:

- **Driver:** Windows NVIDIA driver exposes `/usr/lib/wsl/lib/nvidia-smi`; symlink to `/usr/local/bin` if `nvidia-smi` is not on PATH.
- **Cgroups:** set `no-cgroups = true` under `[nvidia-container-cli]` in `/etc/nvidia-container-runtime/config.toml`.
- **k3s v1.35+:** copy `/etc/containerd/conf.d/99-nvidia.toml` into `/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.d/`.
- **SSH:** WSL port **2222**; homelab pubkey in `authorized_keys`. From blackpearl: `ssh -p 2222 -i ~/.ssh/homelab s4il0r@192.168.10.31`.
- **Windows firewall:** run [scripts/windows-firewall-homelab-desktop.ps1](../../scripts/windows-firewall-homelab-desktop.ps1) as Administrator.

If `nvidia-smi` fails entirely: install a current Windows NVIDIA driver with WSL support.

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

Per-node DCGM metric count:

```bash
kubectl get pods -n monitoring -l app=dcgm-exporter -o wide
curl -s http://<pod-ip>:9400/metrics | grep -c DCGM_FI
```

Grafana **Homelab GPUs (DCGM)** dashboard shows separate rows for `node="engine"` and `node="desktop"`.
