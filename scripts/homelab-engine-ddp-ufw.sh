#!/usr/bin/env bash
# Allow PyTorch DDP / NCCL on engine (run on engine as root).
set -euo pipefail
LAN_CIDR="${LAN_CIDR:-192.168.10.0/24}"
sudo ufw allow from "${LAN_CIDR}" to any port 29500 proto tcp comment 'pytorch-ddp-master'
sudo ufw allow from "${LAN_CIDR}" to any port 1024:65535 proto tcp comment 'nccl-ephemeral'
sudo ufw reload
echo "OK: engine UFW allows DDP master (29500) and NCCL ports (40000-65535) from ${LAN_CIDR}"
