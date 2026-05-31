# Desktop k3s worker (WSL2)

Daily-driver burst node: **Ubuntu 24.04** in WSL2, k3s agent, mirrored LAN IP.

| Field | Value |
|-------|--------|
| Node name | `desktop` |
| LAN IP | `192.168.10.31` |
| Labels | `workload=burst`, `machine=daily-driver` |
| SSH (homelab) | `s4il0r@192.168.10.31` port **2222** (WSL) |

## What was installed

1. **Ubuntu-24.04** WSL distro (default)
2. **`%USERPROFILE%\.wslconfig`** — `networkingMode=mirrored` so WSL gets `192.168.10.31` on `eth0`
3. **`/etc/wsl.conf`** — `systemd=true`, default user `s4il0r`
4. **k3s agent** — same version as blackpearl (`v1.35.5+k3s1`), `--node-ip 192.168.10.31`
5. **OpenSSH in WSL** on port **2222** (Windows OpenSSH keeps port 22)

## Verify cluster

From blackpearl or any machine with kubectl:

```bash
kubectl get nodes -o wide
kubectl get node desktop --show-labels
```

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
- Burst workloads can be scheduled with `nodeSelector: { workload: burst }` once taints/tolerations are added later.
- Windows admin SSH (`julian@192.168.10.31:22`) requires `C:\ProgramData\ssh\administrators_authorized_keys` — use WSL port 2222 for homelab automation instead.
