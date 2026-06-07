# Homelab static storage (engine)

| File | Purpose |
|------|---------|
| `engine-external-pv.yaml` | USB / external disk on **engine** at `/srv/homelab/external` |
| `engine-nvme-pv.yaml` | NVMe on **engine** at `/srv/homelab/nvme` (after LUKS wipe) |

Prometheus TSDB PV lives in [../monitoring/prometheus-engine-pv.yaml](../monitoring/prometheus-engine-pv.yaml).

## Engine external USB

One-time host prep (formats the USB disk — **destroys existing data**):

```bash
# on engine (root)
sudo bash scripts/engine-external-disk-setup.sh

# or from blackpearl (kubectl debug node/engine)
bash scripts/engine-external-disk-apply.sh
```

If format succeeded but mount failed (bad fstab line), run `scripts/engine-external-disk-finish-mount.sh` via the setup pod.

Then apply the PV:

```bash
kubectl apply -f k8s/storage/engine-external-pv.yaml
```

Use in a PVC:

```yaml
spec:
  storageClassName: engine-external
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
```

Pods must schedule on **engine** (`nodeSelector` / affinity for `kubernetes.io/hostname: engine`).

## Engine NVMe (LUKS → ext4)

Wipes **`/dev/nvme0n1p3`** LUKS header, formats ext4, mounts **`/srv/homelab/nvme`**:

```bash
bash scripts/engine-nvme-disk-apply.sh
```

Use `storageClassName: engine-nvme` for PVCs on engine.

## Boot mounts (all homelab disks on engine)

`/srv/homelab/external`, `/srv/homelab/intenso-research`, and `/srv/homelab/nvme` must survive reboot. From **blackpearl**:

```bash
bash scripts/engine-homelab-mounts-apply.sh
```

This writes UUID-based **fstab** lines (`nofail`, long USB timeout) and enables **`engine-homelab-mounts.service`** (runs before `k3s-agent` if a disk is slow to appear).
