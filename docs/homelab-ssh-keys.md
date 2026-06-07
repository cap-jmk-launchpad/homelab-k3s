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

Set key paths in `beelink-cleanup\.env` (see `.env.example`):

```dotenv
HOMELAB_KEY=C:\Users\Julian\.ssh\homelab
BEELINK_KEY=C:\Users\Julian\.ssh\beelink
STAGING_KEY=C:\Users\Julian\.ssh\blackpearl
KUBECONFIG_LOCAL=C:\Users\Julian\Documents\Programming\beelink-cleanup\.kube\config-homelab
```

```powershell
. homelab-k3s\scripts\load-env.ps1
$k = (Get-HomelabDotEnv)["HOMELAB_KEY"]
ssh -i $k s4il0r@192.168.10.41
ssh -i $k s4il0r@engine
ssh -i $k julian@192.168.10.28
```

Blackpearl keeps a copy at `~/.ssh/homelab` for worker onboarding scripts.

## Nodes

| Host | IP | Status |
|------|-----|--------|
| blackpearl | 192.168.10.41 | k3s server |
| engine | 192.168.10.32 | k3s agent, GPU, [Ollama LLM](engine-ollama.md) |
| desktop | 192.168.10.31 | k3s agent (Ubuntu WSL2), SSH port **2222** |
| deck | 192.168.10.26 | k3s agent (arm64 Pi) |
| anch0r | 192.168.10.22 | k3s agent (arm64 Pi) |
| macbook | 192.168.10.28 | **kubectl client** (`julian`); not a k3s worker — [mac-homelab-client.md](mac-homelab-client.md) |

See [desktop-k3s-worker.md](desktop-k3s-worker.md) for WSL setup and [mac-homelab-client.md](mac-homelab-client.md) for the Mac.

Open **6443/tcp** on blackpearl UFW for agents (`sudo ufw allow 6443/tcp`).

## Windows client — agent safety

Private keys live at the paths in `beelink-cleanup\.env` (not in git). Cursor agents have deleted or moved them before; use layered protection:

| Layer | Location | What it does |
|-------|----------|--------------|
| **User hook** | `%USERPROFILE%\.cursor\hooks.json` | Blocks shell `rm`/`del`/`Remove-Item` and tool `Delete`/`Write` on key paths |
| **Cursor rule** | `beelink-cleanup/.cursor/rules/protect-local-secrets.mdc` | Tells agents never to touch keys, `.env`, or kubeconfig |
| **`.cursorignore`** | `beelink-cleanup/.cursorignore` | Keeps agents from indexing private key files |
| **Read-only ACLs** | `beelink-cleanup/scripts/protect-ssh-keys.ps1` | Run after restoring keys — OS-level delete protection |

After restoring keys from blackpearl or Mac:

```powershell
cd C:\Users\Julian\Documents\Programming\beelink-cleanup
.\scripts\verify-local-secrets.ps1
.\scripts\protect-ssh-keys.ps1
```

**Offline backup:** copy the files referenced by `HOMELAB_KEY`, `BEELINK_KEY`, and `STAGING_KEY` in `.env` to a password manager or encrypted USB — not the repo.

### Install user hook (once per PC)

```powershell
mkdir $env:USERPROFILE\.cursor\hooks -Force
Copy-Item homelab-k3s\scripts\cursor-protect-homelab-secrets.py $env:USERPROFILE\.cursor\hooks\protect-homelab-secrets.py
Copy-Item homelab-k3s\scripts\cursor-hooks.example.json $env:USERPROFILE\.cursor\hooks.json
```

Restart Cursor, then confirm the hook appears under **Settings → Hooks**.
