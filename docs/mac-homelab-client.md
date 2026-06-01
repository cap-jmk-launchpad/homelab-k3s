# MacBook — homelab client (`192.168.10.28`)

Julian's Mac on the LAN is **`.28`** → **`192.168.10.28`** (Fritz!box DHCP reservation recommended). It is a **kubectl/SSH client**, not a native k3s worker: k3s agents require Linux (see [k3s-workers.md](k3s-workers.md) for Pi/engine/desktop patterns).

| Item | Value |
|------|--------|
| LAN IP | `192.168.10.28` |
| SSH user | `julian` (macOS login) |
| Cluster API | `https://192.168.10.41:6443` (blackpearl) |
| Automation key | `homelab` / `homelab.pub` (same as other nodes) |
| Mac → cluster pubkey | [scripts/julian-macbook.pub](../scripts/julian-macbook.pub) (optional; for `ssh-copy-id` from Mac to blackpearl) |

## What “join the cluster” means here

| Goal | Approach |
|------|----------|
| SSH without password | [scripts/setup-mac-homelab-ssh.sh](../scripts/setup-mac-homelab-ssh.sh) on the Mac |
| `kubectl` from the Mac | [scripts/copy-kubeconfig-to-mac.sh](../scripts/copy-kubeconfig-to-mac.sh) after SSH keys work |
| Run pods **on** the Mac | Not supported on macOS; use a Linux VM or an existing worker (desktop/engine/deck) |

## 1. One-time on the Mac (password SSH OK)

1. **Remote Login** — System Settings → General → Sharing → **Remote Login** on (allow your user).
2. Copy this repo onto the Mac (or at least `homelab.pub` + `scripts/`).
3. Install cluster keys into `~/.ssh/authorized_keys`:

```bash
cd ~/beelink-cleanup   # or wherever you cloned
bash scripts/setup-mac-homelab-ssh.sh
```

4. (Optional) Harden sshd — disable password auth after keys work:

```bash
sudo sh -c 'printf "%s\n" "PasswordAuthentication no" "KbdInteractiveAuthentication no" > /etc/ssh/sshd_config.d/99-homelab.conf'
sudo sshd -t && sudo launchctl kickstart -k system/com.openssh.sshd
```

## 2. Verify from Windows

```powershell
cd C:\Users\Julian\Documents\Programming\beelink-cleanup
ssh -i .\homelab julian@192.168.10.28 hostname
```

Expected: Mac hostname (e.g. `Julians-MacBook-Air`).

## 3. kubectl on the Mac

From Windows (Git Bash) or blackpearl, once step 2 works:

```bash
bash scripts/copy-kubeconfig-to-mac.sh
```

On the Mac (new shell):

```bash
kubectl get nodes -o wide
```

Install `kubectl` if needed: `brew install kubectl`.

## 4. Optional — Mac SSH to blackpearl

```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub -o IdentityFile=~/.ssh/id_rsa s4il0r@192.168.10.41
# or use scripts/julian-macbook.pub from the repo on blackpearl's authorized_keys
```

## 5. Linux worker on the Mac (advanced)

Only if you need the Mac to **run** cluster workloads: run Ubuntu in **Lima** or a VM, then follow [node-prep.md](node-prep.md) + [join-k3s-agent.sh](../scripts/join-k3s-agent.sh) **inside** that Linux environment with a stable LAN IP. That is separate from this client setup.

## Related

- [homelab-ssh-keys.md](homelab-ssh-keys.md) — key inventory
- [homelab-monitoring.md](homelab-monitoring.md) — copy kubeconfig from blackpearl (Windows path)
- [desktop-k3s-worker.md](desktop-k3s-worker.md) — daily-driver Windows + WSL worker (`.31`)
