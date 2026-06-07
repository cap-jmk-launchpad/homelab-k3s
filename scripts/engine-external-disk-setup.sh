#!/usr/bin/env bash
# Format and mount engine USB disk for homelab K8s (run on engine as root).
# Wipes ENGINE_EXTERNAL_DEV (default /dev/sdb1). Refuses to touch sda (internal OS disk).
set -euo pipefail

MOUNT="${ENGINE_EXTERNAL_MOUNT:-/srv/homelab/external}"
LABEL="${ENGINE_EXTERNAL_LABEL:-homelab-external}"
DEV="${ENGINE_EXTERNAL_DEV:-/dev/sdb1}"
FSTAB_MARKER="homelab-engine-external-usb"

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
if [[ "${root_src}" == "${DEV}"* ]] || findmnt -n "${DEV}" | grep -q ' /$'; then
  echo "Refusing: ${DEV} appears to host the root filesystem" >&2
  exit 1
fi

mkdir -p "${MOUNT}"

if findmnt -n "${MOUNT}" >/dev/null 2>&1; then
  current_src="$(findmnt -n -o SOURCE "${MOUNT}")"
  current_fstype="$(findmnt -n -o FSTYPE "${MOUNT}")"
  if [[ "${current_src}" == "${DEV}" ]] && [[ "${current_fstype}" == "ext4" ]]; then
    echo "Already mounted: ${DEV} -> ${MOUNT} (ext4)"
    exit 0
  fi
fi

# Drop desktop automounts on the same device.
while read -r mp; do
  [[ -n "${mp}" ]] && umount -l "${mp}" 2>/dev/null || umount "${mp}" 2>/dev/null || true
done < <(findmnt -rn -o TARGET -S "${DEV}" 2>/dev/null || true)
sleep 1
if findmnt -rn -S "${DEV}" >/dev/null 2>&1; then
  echo "Device still mounted; trying lazy umount on all targets:" >&2
  findmnt -rn -o TARGET -S "${DEV}" | while read -r mp; do umount -l "${mp}" || true; done
  sleep 2
fi
if findmnt -rn -S "${DEV}" >/dev/null 2>&1; then
  echo "Cannot unmount ${DEV}; stop automount and retry" >&2
  findmnt -S "${DEV}" || true
  exit 1
fi

if blkid -o value -s TYPE "${DEV}" 2>/dev/null | grep -qx ext4; then
  echo "Reusing existing ext4 on ${DEV}"
else
  echo "Formatting ${DEV} as ext4 (label ${LABEL}) — all data on this partition will be lost"
  mkfs.ext4 -F -L "${LABEL}" "${DEV}"
fi

UUID="$(blkid -o value -s UUID "${DEV}")"
grep -q "${FSTAB_MARKER}" /etc/fstab && \
  sed -i "/${FSTAB_MARKER}/d" /etc/fstab
echo "UUID=${UUID} ${MOUNT} ext4 defaults,noatime,nofail,x-systemd.device-timeout=30 0 2 # ${FSTAB_MARKER}" >> /etc/fstab

mount "${MOUNT}"
chmod 0755 "${MOUNT}"

echo "OK: ${DEV} (UUID ${UUID}) mounted at ${MOUNT}"
df -hT "${MOUNT}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS "${DEV}"
