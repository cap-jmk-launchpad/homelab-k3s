#!/bin/bash
# NVIDIA GPU + k3s agent containerd on desktop (Ubuntu 24.04 WSL2).
# Run inside WSL as a user with passwordless sudo (or enter password when prompted).
set -euo pipefail

if ! test -e /usr/lib/wsl/lib/nvidia-smi; then
  echo "WSL NVIDIA libs missing. Install a current Windows NVIDIA driver with WSL support."
  exit 1
fi

sudo ln -sf /usr/lib/wsl/lib/nvidia-smi /usr/local/bin/nvidia-smi
sudo ln -sf /usr/lib/wsl/lib/nvidia-smi /usr/bin/nvidia-smi
nvidia-smi --query-gpu=name --format=csv,noheader

if ! dpkg -l nvidia-container-toolkit 2>/dev/null | grep -q ^ii; then
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg --yes
  echo 'deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/amd64 /' \
    | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  sudo apt-get update
  sudo apt-get install -y nvidia-container-toolkit
fi

# WSL has no GPU cgroups; required for nvidia-container-cli
sudo sed -i 's/#no-cgroups = false/no-cgroups = true/' /etc/nvidia-container-runtime/config.toml

sudo nvidia-ctk runtime configure --runtime=containerd \
  --config /var/lib/rancher/k3s/agent/etc/containerd/config.toml

# k3s v1.35+ (containerd v3) imports config-v3.toml.d, not /etc/containerd/conf.d alone
sudo mkdir -p /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.d
sudo cp /etc/containerd/conf.d/99-nvidia.toml \
  /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.d/99-nvidia.toml

sudo systemctl restart k3s-agent
sleep 5
sudo systemctl is-active k3s-agent

echo "Done. From blackpearl:"
echo "  kubectl label node desktop gpu=nvidia --overwrite"
echo "  kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.capacity.nvidia\\\\.com/gpu"
