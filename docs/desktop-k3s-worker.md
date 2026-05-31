# Desktop k3s worker (WSL2)

Daily-driver burst node: **Ubuntu 24.04** in WSL2, k3s agent, mirrored LAN IP.

| Field | Value |
|-------|--------|
| Node name | `desktop` |
| LAN IP | `192.168.10.31` |
| Labels | `workload=burst`, `gpu=nvidia`, `machine=daily-driver` |
| Default taint | `workload=burst:NoSchedule` (gaming has priority) |
| SSH (homelab) | `s4il0r@192.168.10.31` port **2222** (WSL) |

## Gaming priority (default)

The desktop GPU is for local gaming and daily-driver use. By default the node is **tainted** so cluster training jobs do not land there:

```bash
# on blackpearl (default after setup)
./scripts/desktop-gpu-burst-off.sh
kubectl get node desktop -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu,TAINTS:.spec.taints
```

Engine (`workload=training`) stays always available for cluster GPU work.

## Opt in to burst GPU sharing

When you are **not** gaming and want the cluster to use the desktop GPU (e.g. PyTorch DDP across engine + desktop):

```bash
# on blackpearl
./scripts/desktop-gpu-burst-on.sh
kubectl get nodes engine desktop -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu,BURST:.metadata.labels.burst,TAINTS:.spec.taints
./scripts/k8s-training-smoke.sh ddp
```

When you start gaming again:

```bash
./scripts/desktop-gpu-burst-off.sh
```

Burst / multi-GPU manifests tolerate the desktop taint **and** require `burst=enabled` on the desktop node (set only by `desktop-gpu-burst-on.sh`).

### Windows tray toggle

On the daily-driver PC, run `scripts\desktop-gpu-tray\run.bat` for a system-tray icon (gaming vs cluster burst). See [scripts/desktop-gpu-tray/README.md](../scripts/desktop-gpu-tray/README.md).

## What was installed

1. **Ubuntu-24.04** WSL distro (default)
2. **`%USERPROFILE%\.wslconfig`** — `networkingMode=mirrored` so WSL gets `192.168.10.31` on `eth0`
3. **`/etc/wsl.conf`** — `systemd=true`, default user `s4il0r`
4. **k3s agent** — same version as blackpearl (`v1.35.5+k3s1`), `--node-ip 192.168.10.31`
5. **OpenSSH in WSL** on port **2222** (Windows OpenSSH keeps port 22)
6. **NVIDIA container toolkit** — see [k8s/gpu/README.md](../k8s/gpu/README.md) and [desktop-wsl-setup.sh](../k8s/gpu/desktop-wsl-setup.sh)

## Verify cluster

From blackpearl or any machine with kubectl:

```bash
kubectl get nodes -o wide
kubectl get node desktop --show-labels
kubectl get nodes engine desktop -o custom-columns=NAME:.metadata.name,GPU:.status.capacity.nvidia\\.com/gpu,WORKLOAD:.metadata.labels.workload,TAINTS:.spec.taints
```

Both GPU nodes should report `nvidia.com/gpu: 1` when the device plugin is healthy. If desktop shows `<none>`, check WSL `nvidia-smi`, containerd NVIDIA runtime, and `nvidia-device-plugin` pod logs on `desktop`.

## SSH from blackpearl

WSL ssh listens on **2222** (port 22 is used by Windows OpenSSH):

```bash
ssh -p 2222 -i ~/.ssh/homelab s4il0r@192.168.10.31
```

**One-time (admin PowerShell)** — allow inbound 2222 on the desktop:

```powershell
netsh advfirewall firewall add rule name="WSL Homelab SSH" dir=in action=allow protocol=TCP localport=2222
```

## k3s agent service

Inside WSL:

```bash
wsl -d Ubuntu-24.04
sudo systemctl status k3s-agent
```

After reboot, WSL starts automatically when used; ensure Ubuntu-24.04 is default (`wsl --set-default Ubuntu-24.04`). k3s-agent is enabled via systemd.

## Re-join (if needed)

```powershell
wsl -d Ubuntu-24.04 -u root -- bash /mnt/c/Users/Julian/Documents/Programming/beelink-cleanup/scripts/join-k3s-desktop-wsl.sh
```

Token comes from blackpearl: `sudo cat /var/lib/rancher/k3s/server/node-token`

## Metrics firewall (WSL mirrored)

Standard Windows firewall rules are not enough for mirrored WSL. Run both scripts **elevated** on the desktop host:

```powershell
Get-Content scripts\windows-firewall-homelab-desktop.ps1 | powershell -ExecutionPolicy Bypass -Command -
Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File scripts\windows-firewall-homelab-desktop-hyperv.ps1' -Wait
```

Without the Hyper-V script, `:9100`/`:10250` time out from the LAN and `kubectl top node desktop` stays `<unknown>`.

Verify from blackpearl: `nc -zv 192.168.10.31 9100` and `kubectl top node desktop`.

## Notes

- **podman-machine-default** and **docker-desktop** distros are unchanged; k3s runs only in Ubuntu-24.04.
- Windows admin SSH (`julian@192.168.10.31:22`) requires `C:\ProgramData\ssh\administrators_authorized_keys` — use WSL port 2222 for homelab automation instead.
