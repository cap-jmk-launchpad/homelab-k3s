# Node preparation

Generic first-boot setup for any cluster node (control plane, worker, or edge).

**OS policy:** cluster **server**, **edge**, and standard **worker** nodes require **Debian/Ubuntu** (or Pi arm64). The only Windows-adjacent exception is the optional **WSL2 desktop worker** — see [desktop-k3s-worker.md](desktop-k3s-worker.md). Edge ingress (li-httpd) runs on **Linux blackpearl only** — [platform-requirements.md](platform-requirements.md).

Replace placeholders:

| Placeholder | Example |
|-------------|---------|
| `<admin-user>` | Your automation account |
| `<automation-pubkey-file>` | Path to `homelab.pub` on the machine running the script |
| `<node-name>` | Short hostname |

## 1. Create automation user

During OS install or after first boot:

```bash
sudo useradd -m -s /bin/bash -G sudo <admin-user>
```

## 2. Install automation SSH key

Copy this repo (or just `scripts/`) to the node, then as **root**:

```bash
sudo bash scripts/install-automation-key.sh <automation-pubkey-file>
```

This installs the pubkey for `<admin-user>` and optionally root (if you keep root key access).

## 3. Passwordless sudo (automation only)

As root:

```bash
echo '<admin-user> ALL=(ALL:ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/<admin-user>-nopasswd
sudo chmod 440 /etc/sudoers.d/<admin-user>-nopasswd
sudo visudo -cf /etc/sudoers.d/<admin-user>-nopasswd
```

## 4. SSH hardening

Create `/etc/ssh/sshd_config.d/99-homelab-automation.conf`:

```
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no

Match User <admin-user>
    AuthenticationMethods publickey
    PasswordAuthentication no
```

Apply:

```bash
sudo sshd -t
sudo systemctl reload ssh
```

## 5. Base packages

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  openssh-server sudo curl ca-certificates ufw
```

## 6. Hostname

```bash
sudo hostnamectl set-hostname <node-name>
```

## 7. Firewall (workers and edge)

Default deny incoming; allow SSH:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw --force enable
```

Control plane also needs **6443/tcp** — see [k3s-server.md](k3s-server.md).

## 8. Always-on (recommended for servers)

Mask sleep targets so headless boxes stay reachable:

```bash
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

Optional: configure `logind` to ignore idle/lid actions on laptops used as servers.

## 9. Verify from your workstation

```bash
ssh -i /path/to/homelab <admin-user>@<lan-ip> 'hostname; sudo -n whoami'
```

Expected: `<node-name>` and `root` (via sudo).

## Console recovery (optional)

Physical console autologin for `<admin-user>` on `tty1` can help when SSH breaks. **Do not** treat console autologin as a remote access path — LAN/SSH only for automation.
