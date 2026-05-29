# Fresh install: blackpearl (Majico staging only)

Old WordPress stack is **abandoned**. This box is a clean **Debian Trixie** homelab for **Majico staging** (Podman + self-hosted Supabase + li-httpd edge). See `majico.xyz/deploy/staging/` for app deploy.

Related: [blackpearl-boot-recovery.md](blackpearl-boot-recovery.md) (legacy fstab disaster — **do not repeat bind-mount experiments**).

---

## 1. Debian installer

1. Download **Debian 13 (Trixie)** netinst amd64.
2. Install **minimal** system (no desktop).
3. **Hostname:** `blackpearl`
4. **User:** create `s4il0r` during install (or let setup script create it).
5. Enable **OpenSSH server** in tasksel if offered.

### Partitioning (recommended)

| Mount | Size | Notes |
|-------|------|--------|
| `/` | 32–64 GB | Keep simple — system + Podman images you accept on root |
| `/home` | **rest of disk** | Staging data, Supabase volumes, git clones |
| `/var` | optional separate | Only if you know why; **default: leave on `/`** |
| `/tmp` | optional | **Do not bind-mount `/var` or `/tmp` onto `/home` at boot** |
| swap | 2–8 GB or zram | Your choice |

**Do not** use fstab bind mounts for `/var` → `/home/.disk/var` without a tested boot order. Put heavy data under `/home/s4il0r/staging/` instead.

6. Finish install and reboot.

---

## 2. First boot (local console)

Log in as **root** (installer password) or `s4il0r`.

Copy setup files from your PC:

```powershell
# From Windows (adjust IP after install — check Fritz!box DHCP)
scp -r C:\Users\Julian\Documents\Programming\beelink-cleanup\scripts root@192.168.10.XX:/root/setup/
```

Or clone this repo on the server if you add a remote later.

---

## 3. Run one-shot access setup (as root)

```bash
chmod +x /root/setup/setup-blackpearl-access.sh
bash /root/setup/setup-blackpearl-access.sh
reboot
```

This script:

- Installs **OpenSSH**, **Podman**, **ufw**
- Installs agent **SSH public key** from `scripts/authorized_keys`
- **Key-only SSH** for `s4il0r` (no password auth)
- **NOPASSWD sudo** for `s4il0r` (automation — **not** passwordless root login)
- **Disables root SSH**
- **Console autologin** for `s4il0r` on **tty1** (physical recovery only)
- Opens **UFW** for SSH only (uncomment staging ports in script when ready)
- Creates `/home/s4il0r/staging/{majico.xyz,supabase}`

---

## 4. Verify from Windows

Copy `.env.example` → `.env` locally (optional `STAGING_PASSWORD` not needed after setup).

```powershell
ssh -i C:\Users\Julian\Documents\Programming\beelink-cleanup\beelink s4il0r@blackpearl "hostname; sudo whoami; podman --version"
```

Expected: `blackpearl`, `root`, podman version.

---

## 5. Agent public key (verify)

The key in `scripts/authorized_keys` must match your private key `beelink`:

```powershell
ssh-keygen -y -f C:\Users\Julian\Documents\Programming\beelink-cleanup\beelink
```

Fingerprint (RSA): compare with what you trust on the agent laptop.

---

## 6. Majico staging next steps

On the server (after SSH works):

```bash
# GitHub token from Programming/li/.env.github
export GH_TOKEN=...
bash /home/s4il0r/staging/majico.xyz/deploy/staging/scripts/blackpearl-bootstrap.sh
```

Full runbook: `majico.xyz/deploy/staging/README.md` and [blackpearl-staging.md](blackpearl-staging.md).

---

## SSH access model

| Account | Access |
|---------|--------|
| `s4il0r` | Key-only SSH + **NOPASSWD sudo** (automation) |
| `root` | Key-only SSH (`PermitRootLogin prohibit-password`) � same pubkey as `s4il0r` |
| Password auth | **Disabled** globally |

Pubkey file: `scripts/blackpearl.pub` (install to both `s4il0r` and `root` `authorized_keys`).

Run full prep:

```bash
sudo bash /root/setup/apply-server-prep.sh
```

## Security model (homelab staging)

| Choice | Rationale |
|--------|-----------|
| **Key-only SSH** | No brute-force on passwords |
| **Root login disabled** | Use `sudo` as `s4il0r`; full root SSH is discouraged even with keys |
| **NOPASSWD sudo for s4il0r** | Lets Cursor/agent run `apt`, `podman`, `systemctl` without storing sudo password |
| **Console autologin** | Physical keyboard only — **not** remote; for recovery if SSH breaks |
| **UFW default deny** | Open 22 now; 8080/8443 when staging edge is live |

### Optional: root SSH with key (not recommended)

If you insist, after setup:

```bash
sudo mkdir -p /root/.ssh
sudo cp /home/s4il0r/.ssh/authorized_keys /root/.ssh/
sudo chmod 700 /root/.ssh && sudo chmod 600 /root/.ssh/authorized_keys
# Still keep PermitRootLogin no unless you explicitly change sshd — we do not automate this.
```

Prefer **s4il0r + sudo** for all automation.

---

## 7. DNS

Point or use Fritz!box local name:

- `blackpearl` → DHCP reservation (stable IP)
- Later: `staging.majico.xyz`, `api.staging.majico.xyz` → this host

---

## One-liner after install

On the **new box as root** (after copying `scripts/`):

```bash
bash /root/setup/setup-blackpearl-access.sh && reboot
```

Then from **Windows**:

```powershell
ssh -i C:\Users\Julian\Documents\Programming\beelink-cleanup\beelink s4il0r@blackpearl "sudo podman info"
```
---

## 8. Always-on (no sleep / hibernate)

Staging box must stay awake. Run once as root (included in `setup-blackpearl-access.sh`):

```bash
bash /root/setup/disable-sleep.sh
```

This masks `sleep.target`, `suspend.target`, `hibernate.target`, `hybrid-sleep.target` and sets `/etc/systemd/logind.conf.d/nosleep.conf` (`IdleAction=ignore`, lid switch ignored).

Verify:

```bash
systemctl status sleep.target
cat /etc/systemd/logind.conf.d/nosleep.conf
```

Optional (manual): `apt purge systemd-sleep` only if you understand the impact on your kernel/firmware.
