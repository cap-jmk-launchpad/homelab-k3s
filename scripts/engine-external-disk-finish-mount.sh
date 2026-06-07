#!/usr/bin/env bash
# Fix fstab + mount after format (engine host).
set -euo pipefail
MOUNT="${ENGINE_EXTERNAL_MOUNT:-/srv/homelab/external}"
DEV="${ENGINE_EXTERNAL_DEV:-/dev/sdb1}"
MARKER="homelab-engine-external-usb"
UUID="$(blkid -o value -s UUID "${DEV}")"
mkdir -p "${MOUNT}"
sed -i "/${MARKER}/d" /etc/fstab
grep -v 'homelab engine external usb' /etc/fstab > /tmp/fstab.new || cp /etc/fstab /tmp/fstab.new
mv /tmp/fstab.new /etc/fstab
echo "UUID=${UUID} ${MOUNT} ext4 defaults,noatime,nofail,x-systemd.device-timeout=30 0 2 # ${MARKER}" >> /etc/fstab
mount "${MOUNT}" || mount UUID="${UUID}" "${MOUNT}"
chmod 0755 "${MOUNT}"
df -hT "${MOUNT}"
