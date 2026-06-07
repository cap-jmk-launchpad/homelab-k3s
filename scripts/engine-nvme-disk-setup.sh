#!/usr/bin/env bash
# Wipe LUKS on engine NVMe, format ext4, mount for homelab (run on engine as root).
# Wipes ENGINE_NVME_DEV (default /dev/nvme0n1p3). Refuses sda (internal OS disk).
set -euo pipefail

MOUNT="${ENGINE_NVME_MOUNT:-/srv/homelab/nvme}"
LABEL="${ENGINE_NVME_LABEL:-homelab-nvme}"
DEV="${ENGINE_NVME_DEV:-/dev/nvme0n1p3}"
FSTAB_MARKER="homelab-engine-nvme-luks"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

if [[ "${DEV}" == *sda* ]]; then
  echo "Refusing to use internal OS disk: ${DEV}" >&2
  exit 1
fi

if [[ ! -b "${DEV}" ]]; then
  echo "Block device not found: ${DEV}" >&2
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
  exit 1
fi

root_src="$(findmnt -n -o SOURCE / || true)"
if [[ "${root_src}" == "${DEV}"* ]] || findmnt -n "${DEV}" 2>/dev/null | grep -q ' /$'; then
  echo "Refusing: ${DEV} appears to host the root filesystem" >&2
  exit 1
fi

mkdir -p "${MOUNT}"

if findmnt -n "${MOUNT}" >/dev/null 2>&1; then
  current_src="$(findmnt -n -o SOURCE "${MOUNT}")"
  current_fstype="$(findmnt -n -o FSTYPE "${MOUNT}")"
  if [[ "${current_src}" == "${DEV}" ]] && [[ "${current_fstype}" == "ext4" ]]; then
    echo "Already mounted: ${DEV} -> ${MOUNT} (ext4)"
    df -hT "${MOUNT}"
    exit 0
  fi
fi

echo "==> Unmounting any mounts on ${DEV}"
while read -r mp; do
  [[ -n "${mp}" ]] && umount -l "${mp}" 2>/dev/null || umount "${mp}" 2>/dev/null || true
done < <(findmnt -rn -o TARGET -S "${DEV}" 2>/dev/null || true)

echo "==> Closing LUKS mappings for ${DEV} (if any)"
if command -v cryptsetup >/dev/null 2>&1; then
  while read -r name; do
    [[ -z "${name}" || "${name}" == "control" ]] && continue
    if cryptsetup status "${name}" 2>/dev/null | grep -q "${DEV}"; then
      while read -r mp; do
        [[ -n "${mp}" ]] && umount -l "${mp}" 2>/dev/null || true
      done < <(findmnt -rn -o TARGET "/dev/mapper/${name}" 2>/dev/null || true)
      cryptsetup close "${name}" || true
    fi
  done < <(ls /dev/mapper/ 2>/dev/null || true)
  if cryptsetup isLuks "${DEV}" 2>/dev/null; then
    echo "Removing LUKS header on ${DEV} (all data lost)"
    cryptsetup luksErase -q "${DEV}" || wipefs -af "${DEV}"
  fi
else
  echo "cryptsetup not found; using wipefs only"
  wipefs -af "${DEV}" || true
fi

if findmnt -rn -S "${DEV}" >/dev/null 2>&1; then
  echo "Device still mounted; aborting" >&2
  findmnt -S "${DEV}" || true
  exit 1
fi

wipefs -af "${DEV}" 2>/dev/null || true

if blkid -o value -s TYPE "${DEV}" 2>/dev/null | grep -qx ext4; then
  echo "Reusing existing ext4 on ${DEV}"
else
  echo "Formatting ${DEV} as ext4 (label ${LABEL}) — all data on this partition will be lost"
  mkfs.ext4 -F -L "${LABEL}" "${DEV}"
fi

UUID="$(blkid -o value -s UUID "${DEV}")"
grep -q "${FSTAB_MARKER}" /etc/fstab && sed -i "/${FSTAB_MARKER}/d" /etc/fstab
echo "UUID=${UUID} ${MOUNT} ext4 defaults,noatime,nofail,x-systemd.device-timeout=30 0 2 # ${FSTAB_MARKER}" >> /etc/fstab

mount "${MOUNT}"
chmod 0755 "${MOUNT}"

echo "OK: ${DEV} (UUID ${UUID}) mounted at ${MOUNT}"
df -hT "${MOUNT}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS | grep -E '^(NAME|sda|sdb|sdc|nvme)' || lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
