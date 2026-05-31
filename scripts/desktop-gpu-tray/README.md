# Desktop GPU burst tray (Windows)

Small system-tray app for Julian's daily-driver PC. Toggles whether the desktop WSL k3s worker shares its GPU with the homelab cluster.

| Tray tooltip | Meaning |
|--------------|---------|
| **Gaming (GPU for me)** | Burst off — `workload=burst:NoSchedule` taint on `desktop` |
| **Cluster burst (share GPU)** | Burst on — taint removed, `burst=enabled` label set |

Right-click the tray icon (colored dot next to the clock):

- **Gaming mode (GPU for me)** — runs `desktop-gpu-burst-off.sh` on blackpearl via SSH
- **Cluster burst (share GPU)** — runs `desktop-gpu-burst-on.sh`
- **Refresh status** — re-reads node labels/taints from the cluster
- **Quit**

Icon colors: blue = gaming, green = cluster burst, gray = unknown/error.

## Prerequisites

- Windows 10/11
- Python 3.10+ on PATH
- OpenSSH client (`ssh` in PowerShell)
- SSH key at repo root: `homelab` (same key used for `s4il0r@192.168.10.41`)
- blackpearl reachable on LAN (`192.168.10.41`)

Optional environment overrides:

| Variable | Default |
|----------|---------|
| `HOMELAB_SSH_KEY` | `<repo>/homelab` |
| `HOMELAB_SSH_HOST` | `s4il0r@192.168.10.41` |
| `HOMELAB_GPU_SCRIPTS` | `~/homelab-k3s/scripts` |

## Install and run

From the repo root:

```bat
scripts\desktop-gpu-tray\run.bat
```

First launch installs `pystray` and `Pillow` into your user Python environment.

## Start at login (optional)

```bat
scripts\desktop-gpu-tray\install-startup.bat
```

Creates `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Desktop GPU Burst.lnk`.

## Manual CLI (same as tray)

On blackpearl:

```bash
./scripts/desktop-gpu-burst-on.sh   # share GPU
./scripts/desktop-gpu-burst-off.sh  # gaming priority
```

See also [docs/desktop-k3s-worker.md](../../docs/desktop-k3s-worker.md).
