#!/usr/bin/env bash
# Ensure engine homelab data disks are listed in /etc/fstab and mounted (run on engine as root).
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

if [[ "$(hostname -s)" != "engine" ]]; then
  echo "Refusing: expected hostname engine, got $(hostname -s)" >&2
  exit 1
fi

HOMELAB=/srv/homelab
MOUNT_EXTERNAL="${HOMELAB}/external"
MOUNT_INTENSO="${HOMELAB}/intenso-research"
MOUNT_NVME="${HOMELAB}/nvme"
MOUNT_LIP="/var/lib/lip-registry"

DEV_EXTERNAL="${ENGINE_EXTERNAL_DEV:-/dev/sdb1}"
DEV_INTENSO="${ENGINE_INTENSO_DEV:-/dev/sdc1}"
DEV_NVME="${ENGINE_NVME_DEV:-/dev/nvme0n1p3}"

MARKER_EXTERNAL="homelab-engine-external-usb"
MARKER_INTENSO="homelab-engine-intenso"
MARKER_NVME="homelab-engine-nvme-luks"
MARKER_LIP="homelab-engine-lip-registry"

FSTAB_OPTS_USB="defaults,noatime,nofail,x-systemd.device-timeout=120"
FSTAB_OPTS_NVME="defaults,noatime,nofail,x-systemd.device-timeout=30"

uuid_for() {
  local mount=$1 dev=$2
  if findmnt -rn "${mount}" >/dev/null 2>&1; then
    findmnt -n -o UUID -M "${mount}"
  elif [[ -b "${dev}" ]]; then
    blkid -o value -s UUID "${dev}"
  else
    echo "Cannot resolve UUID for ${mount} (${dev} missing)" >&2
    return 1
  fi
}

strip_homelab_fstab() {
  local tmp
  tmp="$(mktemp)"
  grep -v "${MARKER_EXTERNAL}" /etc/fstab | grep -v "${MARKER_INTENSO}" | grep -v "${MARKER_NVME}" | grep -v "${MARKER_LIP}" \
    | grep -v 'homelab engine external usb' \
    | grep -v "${MOUNT_INTENSO}" \
    | grep -v "${MOUNT_EXTERNAL}" \
    | grep -v "${MOUNT_NVME}" \
    | grep -v "${MOUNT_LIP}" > "${tmp}" || cp /etc/fstab "${tmp}"
  mv "${tmp}" /etc/fstab
}

add_fstab_line() {
  local uuid=$1 mount=$2 opts=$3 marker=$4
  echo "UUID=${uuid} ${mount} ext4 ${opts} 0 2 # ${marker}" >> /etc/fstab
}

install_boot_service() {
  local unit=/etc/systemd/system/engine-homelab-mounts.service
  local script=/usr/local/sbin/engine-homelab-mounts-boot.sh
  install -Dm755 /dev/stdin "${script}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for mp in /srv/homelab/external /srv/homelab/intenso-research /srv/homelab/nvme /var/lib/lip-registry; do
  [[ -d "${mp}" ]] || mkdir -p "${mp}"
  if ! mountpoint -q "${mp}"; then
    mount "${mp}" || true
  fi
done
EOF
  install -Dm644 /dev/stdin "${unit}" <<'EOF'
[Unit]
Description=Mount engine homelab data disks (/srv/homelab)
DefaultDependencies=no
After=local-fs.target
Before=k3s-agent.service
ConditionPathExists=/srv/homelab

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/engine-homelab-mounts-boot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable engine-homelab-mounts.service
}

echo "==> Ensure mount points exist"
mkdir -p "${MOUNT_EXTERNAL}" "${MOUNT_INTENSO}" "${MOUNT_NVME}" "${MOUNT_LIP}"

echo "==> Resolve filesystem UUIDs"
UUID_EXTERNAL="$(uuid_for "${MOUNT_EXTERNAL}" "${DEV_EXTERNAL}")"
UUID_INTENSO="$(uuid_for "${MOUNT_INTENSO}" "${DEV_INTENSO}")"
UUID_NVME="$(uuid_for "${MOUNT_NVME}" "${DEV_NVME}")"

echo "==> Rewrite homelab fstab entries"
strip_homelab_fstab
add_fstab_line "${UUID_EXTERNAL}" "${MOUNT_EXTERNAL}" "${FSTAB_OPTS_USB}" "${MARKER_EXTERNAL}"
add_fstab_line "${UUID_INTENSO}" "${MOUNT_INTENSO}" "${FSTAB_OPTS_USB}" "${MARKER_INTENSO}"
add_fstab_line "${UUID_NVME}" "${MOUNT_NVME}" "${FSTAB_OPTS_NVME}" "${MARKER_NVME}"
add_fstab_line "${UUID_EXTERNAL}" "${MOUNT_LIP}" "${FSTAB_OPTS_USB}" "${MARKER_LIP}"

echo "==> Install boot mount service"
install_boot_service

echo "==> Mount all fstab entries"
systemctl daemon-reload
mount -a
/usr/local/sbin/engine-homelab-mounts-boot.sh

echo "==> Verify"
failed=0
for mp in "${MOUNT_EXTERNAL}" "${MOUNT_INTENSO}" "${MOUNT_NVME}" "${MOUNT_LIP}"; do
  if mountpoint -q "${mp}"; then
    findmnt -rn -o TARGET,SOURCE,FSTYPE "${mp}"
  else
    echo "MISSING mount: ${mp}" >&2
    failed=1
  fi
done
echo
grep homelab-engine /etc/fstab
echo
systemctl is-enabled engine-homelab-mounts.service
if [[ "${failed}" -ne 0 ]]; then
  exit 1
fi
echo "OK: homelab disks configured for boot"
