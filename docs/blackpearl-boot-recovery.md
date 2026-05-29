# blackpearl boot recovery (fstab bind-mount rollback)

**Symptom:** Machine powers on but does not finish boot (hang, emergency mode, or no SSH).  
**Likely cause:** `/etc/fstab` was changed to bind-mount `/var` and `/tmp` onto `/home/.disk/…` before `/home` was reliably mounted at boot.

**Your data is safe:** copies live on the large `/home` disk at `/home/.disk/var` and `/home/.disk/tmp`. Rolling back `fstab` does **not** delete them.

**Backup to restore:** `/etc/fstab.bak-bind-migrate-20260528`

---

## Quick fix (copy-paste at console)

If you get any shell as **root** (emergency mode, single-user, or GRUB `init=/bin/bash`):

```bash
mount -o remount,rw /
cp -a /etc/fstab.bak-bind-migrate-20260528 /etc/fstab
cat /etc/fstab
mount -a
sync
reboot
```

After reboot, SSH should work again:

```powershell
ssh -i C:\Users\Julian\Documents\Programming\beelink-cleanup\beelink s4il0r@blackpearl
```

---

## Option A — GRUB: emergency shell (recommended)

1. Power on the Beelink. At the **GRUB** menu, highlight the Debian entry.
2. Press **`e`** (edit).
3. Find the line starting with **`linux`** (or `linuxefi`).
4. Move to the **end** of that line (after `quiet` or `ro`) and add **one** of:

   ```text
   systemd.unit=emergency.target
   ```

   Or if that fails:

   ```text
   init=/bin/bash
   ```

5. Press **Ctrl+X** or **F10** to boot.
6. You should get a root shell (emergency) or a minimal bash.

**If root is read-only:**

```bash
mount -o remount,rw /
```

**Restore fstab:**

```bash
ls -la /etc/fstab.bak-bind-migrate-20260528
cp -a /etc/fstab.bak-bind-migrate-20260528 /etc/fstab
```

**Verify fstab** — you should see separate UUID lines for `/`, `/home`, `/var`, `/tmp` (and **no** bind lines for `/home/.disk/var` → `/var`):

```bash
grep -v '^#' /etc/fstab | grep -v '^$'
```

**Test mounts before reboot:**

```bash
mount -a
findmnt / /home /var /tmp
df -h / /home /var /tmp
```

**Reboot:**

```bash
sync
reboot
```

---

## Option B — Drops into emergency mode automatically

1. Log in as **root** (console password) or **s4il0r** if permitted.
2. Run the **Quick fix** block at the top of this doc.
3. Reboot.

If `mount -a` errors, still restore fstab and reboot — the old layout mounts `/var` and `/tmp` from their own partitions again.

---

## Option C — Live USB (last resort)

Use if GRUB edit does not work or disk will not mount.

1. Boot **Debian/Ubuntu live USB**.
2. Identify partitions (adjust if your layout differs):

   ```bash
   lsblk -f
   ```

   Typical on this machine:

   | Partition   | Mount | Role        |
   |-------------|-------|-------------|
   | `nvme0n1p2` | `/`   | root (~23G) |
   | `nvme0n1p6` | `/home` | large data |
   | `nvme0n1p3` | `/var`  | var        |
   | `nvme0n1p5` | `/tmp`  | tmp        |

3. Mount root:

   ```bash
   sudo mount /dev/nvme0n1p2 /mnt
   sudo mount /dev/nvme0n1p6 /mnt/home
   sudo mount /dev/nvme0n1p3 /mnt/var
   sudo mount /dev/nvme0n1p5 /mnt/tmp
   ```

4. Restore fstab on disk:

   ```bash
   sudo cp -a /mnt/etc/fstab.bak-bind-migrate-20260528 /mnt/etc/fstab
   sudo cat /mnt/etc/fstab
   sync
   sudo umount -R /mnt
   reboot
   ```

---

## After boot succeeds

Run on the server:

```bash
# Mounts
findmnt / /home /var /tmp
df -h / /home /var /tmp

# Failed systemd units
systemctl --failed --no-pager
systemctl --user --failed --no-pager

# Core services
systemctl is-active ssh nginx
ss -ltnp | grep -E '9071|9070'

# WordPress podman (user units)
systemctl --user start pod-wordpress-it-freelancing.service
systemctl --user start container-mariadb-wordpress-it-freelancing-container.service
systemctl --user start container-wordpress-it-freelancing-container.service
sudo systemctl start nginx

curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1:9071/
```

From Windows:

```powershell
ssh -i C:\Users\Julian\Documents\Programming\beelink-cleanup\beelink s4il0r@blackpearl "hostname; systemctl is-active ssh nginx"
```

---

## What went wrong

The migration added fstab entries like:

```fstab
/home/.disk/var /var none bind,x-systemd.requires-mounts-for=/home 0 0
/home/.disk/tmp /tmp none bind,x-systemd.requires-mounts-for=/home 0 0
```

and disabled the original `/var` and `/tmp` partition mounts.

At early boot, systemd often needs **`/var`** (logs, `systemd` state, `sshd` keys, Podman) **before** `/home` is fully available. Bind-mounting `/var` from `/home/.disk/var` can deadlock or fail silently → hang, failed units, no SSH.

The copied data under `/home/.disk/var` remains intact for a future, safer migration.

---

## Safe path to merge `/var` onto `/home` later (do not skip steps)

1. **Boot must be stable** with classic fstab (this rollback).
2. Plan during maintenance window; full backup WordPress + `/home/.disk/var`.
3. Use explicit boot ordering, e.g.:

   ```fstab
   UUID=... /home ext4 defaults 0 2
   /home/.disk/var /var none bind,x-systemd.after=home.mount,x-systemd.requires-mounts-for=/home 0 0
   ```

4. **Before reboot:** with current fstab still active, verify:

   ```bash
   sudo mount --bind /home/.disk/var /mnt/var-test
   ls /mnt/var-test/lib
   sudo umount /mnt/var-test
   sudo mount -a
   findmnt /var /tmp /home
   ```

5. Reboot only when `mount -a` succeeds and `systemctl list-dependencies home.mount` looks correct.
6. Keep `/etc/fstab.bak-*` snapshots.

Alternative with less boot risk: **grow root** or keep heavy data only under `/home` without bind-mounting `/var`.

---

## Remote fstab restore (if SSH works but system is degraded)

From your PC (password via sudo on server — use console if SSH is down):

```bash
ssh -i ... s4il0r@blackpearl
sudo cp -a /etc/fstab.bak-bind-migrate-20260528 /etc/fstab
sudo mount -a
sudo reboot
```

**Do not remove `openssh-server`.** Only fix `fstab` and reset failed units for removed pods after the system boots.
