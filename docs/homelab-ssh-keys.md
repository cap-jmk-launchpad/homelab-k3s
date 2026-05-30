# Homelab cluster SSH key

Dedicated **homelab** key for automation between cluster nodes (separate from legacy `blackpearl` key).

| File | On disk | Git |
|------|---------|-----|
| `homelab` | Private key | **gitignored** — back up offline |
| `homelab.pub` | Public key | committed |

## Install on a node

```bash
sudo bash scripts/install-homelab-key.sh scripts/homelab.pub
```

## Use from your PC

```powershell
ssh -i C:\Users\Julian\Documents\Programming\beelink-cleanup\homelab s4il0r@engine
ssh -i C:\Users\Julian\Documents\Programming\beelink-cleanup\homelab s4il0r@192.168.10.41
ssh -i C:\Users\Julian\Documents\Programming\beelink-cleanup\homelab root@engine
```

Blackpearl keeps a copy at `~/.ssh/homelab` for worker onboarding scripts.

## Nodes

| Host | IP | Status |
|------|-----|--------|
| blackpearl | 192.168.10.41 | k3s server |
| engine | 192.168.10.32 | k3s agent, GPU |
| desktop | 192.168.10.31 | next — WSL or native Linux |
| raspberries | TBD | after desktop |

Open **6443/tcp** on blackpearl UFW for agents (`sudo ufw allow 6443/tcp`).
