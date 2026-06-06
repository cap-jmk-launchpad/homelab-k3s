# Homelab k3s monitoring

Cluster control plane: **blackpearl** (`192.168.10.41` SSH, node IP often `192.168.10.33`).

## What is installed

| Component | Namespace | Notes |
|-----------|-----------|-------|
| metrics-server | `kube-system` | k3s default; `kubectl top` |
| kube-prometheus-stack | `monitoring` | Prometheus + Grafana + node-exporter |
| NVIDIA device plugin | `kube-system` | DaemonSet on `gpu=nvidia` nodes only |
| DCGM exporter | `monitoring` | DaemonSet on `gpu=nvidia` (engine + desktop) |

**Prometheus** (TSDB) runs on **engine** with persistent storage on the engine HDD. **Grafana**, **Alertmanager**, and the **prometheus-operator** stay on **blackpearl** (`kubernetes.io/hostname=blackpearl`). **node-exporter** runs on all nodes (arm64 Pis included).

`majico-staging` is untouched.

Manifests: [k8s/monitoring/](../k8s/monitoring/), GPU: [k8s/gpu/](../k8s/gpu/).

## SigNoz (OTel logs, traces, metrics)

**SigNoz** on **blackpearl** (`signoz` namespace): UI **NodePort 30301**, ClickHouse on `local-path`. Collection via **k8s-infra** DaemonSet on all nodes. **Logs, traces, and OTel metrics** via **k8s-infra** DaemonSet on all nodes. **Prometheus + Grafana** remain the primary infra metrics UI.

- **Docs:** [homelab-signoz.md](./homelab-signoz.md)
- **Deploy:** `bash scripts/homelab-deploy-signoz.sh`

## Logging (SigNoz)

Pod stdout/stderr is collected by **SigNoz k8s-infra** and searchable in the SigNoz UI.

- **Docs:** [homelab-signoz.md](./homelab-signoz.md) (primary), [homelab-logging.md](./homelab-logging.md) (short pointer + kubectl)
- **Deploy:** ash scripts/homelab-deploy-signoz.sh


## Grafana (LAN)

- **URL:** `http://192.168.10.41:30300` (or `http://192.168.10.33:30300` via node IP)
- **Port:** NodePort `30300`
- **User:** `admin`
- **Password:** set at Helm deploy (`--set grafana.adminPassword=...`). Not stored in git. Retrieve from the cluster secret (on blackpearl): `kubectl get secret -n monitoring prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo`. Store in your password manager; `/tmp/monitoring-secrets.env` was removed 2026-05-30.

Default dashboards: Kubernetes / Node Exporter / Prometheus.

### Cluster resources dashboard (all nodes)

Provisioned from git via ConfigMap sidecar (`grafana_dashboard=1`):

- **URL:** `http://192.168.10.41:30300/d/homelab-cluster-resources/homelab-cluster-resources`
- **UID:** `homelab-cluster-resources`
- **Refresh:** default **5s**; global min **1s** via `GF_DASHBOARDS_MIN_REFRESH_INTERVAL` and `[dashboards] default_refresh_intervals` in [kube-prometheus-stack-values.yaml](../k8s/monitoring/kube-prometheus-stack-values.yaml). Avoid `[unified_alerting] min_refresh_interval` (CrashLoop). Timepickers list **1s**, **2s**, **5s**, �

| Row | Metrics source |
|-----|----------------|
| Cluster totals | `node_memory_*`, `node_cpu_seconds_total`, `DCGM_FI_DEV_GPU_UTIL` |
| Physical storage | `node_filesystem_*` (ext4/xfs/vfat/btrfs; excludes tmpfs, boot, credentials) |
| Per-node memory / CPU | node-exporter + `kube_node_info` join for k8s node names |
| Network RX/TX | `node_network_*` excluding CNI/veth/docker bridges |
| GPU | DCGM on `engine` + `desktop` (`node` label from ServiceMonitor) |
| Snapshot table | Instant queries merged by `node` (includes Disk % / used / total columns) |

Uses **MemAvailable** (not MemFree) for accurate memory %. Does not rely on upstream kube dashboard `$cluster` variable.

Deploy / update:

```bash
bash scripts/homelab-deploy-dashboards.sh
# After values change (refresh intervals):
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f k8s/monitoring/kube-prometheus-stack-values.yaml \
  --reuse-values
```

Nodes missing from panels (e.g. **desktop** until firewall/DCGM fixed) simply omit series; the dashboard still works for scraped nodes.

### Upstream “Kubernetes / Compute Resources / Cluster” dashboard

URL: `/d/efa86fd1d0c121a26444b636a3f509a8/kubernetes-compute-resources-cluster`

| Issue | Root cause | Fix applied |
|-------|------------|-------------|
| Empty **`$cluster`** dropdown (`var-cluster=` in URL) | Prometheus had no `cluster` label on scraped metrics | `externalLabels.cluster: homelab` plus `metricRelabelings` on node-exporter and kube-state-metrics in values |
| Memory % low / inconsistent with homelab dashboard | node-exporter on **desktop** not scraped (4/5 nodes); upstream mixes node-exporter util with kube-state allocatable | Use **Homelab Cluster Resources** above for accurate node-exporter totals; open **9100/tcp** + **10250/tcp** on desktop Windows host ([windows-firewall-homelab-desktop-apply.ps1](../scripts/windows-firewall-homelab-desktop-apply.ps1)) |

After Helm upgrade, pick **`homelab`** in the `$cluster` dropdown (or wait for new samples with the label).

### GPU dashboard (per-node + cluster)

Import [k8s/monitoring/homelab-gpu-dashboard.json](../k8s/monitoring/homelab-gpu-dashboard.json):

1. Grafana → **Dashboards** → **New** → **Import**
2. Upload JSON or paste file contents
3. Select Prometheus datasource (uid `prometheus` if unchanged)

Dashboard **Homelab GPUs (DCGM)** (`uid: homelab-gpu-dcgm`):

| Panel | PromQL idea |
|-------|-------------|
| Cluster utilization | `sum(DCGM_FI_DEV_GPU_UTIL)` and `avg(...)` across all DCGM targets |
| Per-node utilization | `DCGM_FI_DEV_GPU_UTIL` — legend uses `node` label from ServiceMonitor relabel |
| Engine / Desktop rows | `DCGM_FI_DEV_GPU_UTIL{node="engine"}` and `{node="desktop"}` |

Alternative: import community dashboard **12239** (NVIDIA DCGM Exporter) and add the same cluster panels.

ServiceMonitor relabels `node` and `pod` so each GPU exporter is distinct in Prometheus (`instance` = scrape address, `node` = Kubernetes node name).

## Prometheus

In-cluster: `http://prometheus-stack-prometheus.monitoring.svc:9090` (ClusterIP). Use Grafana Explore or port-forward for ad-hoc queries.

**Retention:** **180 days** (6 months). TSDB size capped at 200GB (`retentionSize`); time-based cap is `retention: 180d` in [kube-prometheus-stack-values.yaml](../k8s/monitoring/kube-prometheus-stack-values.yaml).

**Storage (engine HDD):**

| Item | Value |
|------|--------|
| Node | `engine` (`192.168.10.32`) |
| Disk | `sda2` → `/` (465G HDD; NVMe LUKS is separate and unused) |
| Host path | `/srv/homelab/prometheus` |
| PV / StorageClass | `prometheus-engine-tsdb` / `prometheus-engine` ([prometheus-engine-pv.yaml](../k8s/monitoring/prometheus-engine-pv.yaml)) |
| Free space (typical) | ~320G on `/` — headroom for ~200G TSDB cap plus OS/training data |

### Engine external USB disk

| Item | Value |
|------|--------|
| Block device | `sdb1` (internal OS disk is `sda`) |
| Host mount | `/srv/homelab/external` (ext4, fstab UUID, `nofail`) |
| K8s StorageClass | `engine-external` |
| K8s PV | `engine-external-data` (900Gi, hostPath, engine only) |
| Grafana | Included in **Physical storage** panels on engine |

One-time host prep + PV (formats USB — **wipes disk**):

```bash
bash scripts/engine-external-disk-apply.sh
```

Use in workloads (must schedule on **engine**):

```yaml
storageClassName: engine-external
```

Smoke test:

```bash
kubectl apply -f k8s/storage/engine-external-test.yaml
kubectl -n homelab-storage-test wait --for=condition=Ready pod/engine-external-write-test --timeout=60s
kubectl -n homelab-storage-test logs engine-external-write-test
kubectl delete -f k8s/storage/engine-external-test.yaml
```

Check on engine:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS /dev/sdb
df -hT /srv/homelab/external
```

Prepare on engine (once):

```bash
sudo mkdir -p /srv/homelab/prometheus
sudo chown -R 1000:2000 /srv/homelab/prometheus
```

Samples older than 180 days are dropped automatically. Older samples may also be dropped when `retentionSize` (200GB) is exceeded.

## GPU metrics (engine + desktop)

Nodes must be labeled `gpu=nvidia` (and optionally `workload=training`). Apply GPU stack from [k8s/gpu/README.md](../k8s/gpu/README.md):

```bash
kubectl apply -f k8s/gpu/nvidia-runtimeclass.yaml
kubectl apply -f k8s/gpu/nvidia-device-plugin.yaml
kubectl apply -f k8s/monitoring/dcgm-exporter.yaml
```

Verify on blackpearl:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.capacity.nvidia\\.com/gpu
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds -o wide
kubectl get pods -n monitoring -l app=dcgm-exporter -o wide
```

DCGM metric count per pod (from engine host, replace pod IP):

```bash
curl -s http://<dcgm-pod-ip>:9400/metrics | grep -c DCGM_FI
```

Prometheus should show **one target per GPU node** (distinct `instance`, shared `job`, different `node` label).

### Engine (`192.168.10.32`)

- Host: `nvidia-smi`, `nvidia-container-toolkit`, k3s agent imports `/etc/containerd/conf.d/99-nvidia.toml`
- After `systemctl restart k3s-agent`, if pods fail with missing CNI plugins, run [engine-cni-opt-bin.sh](../k8s/gpu/engine-cni-opt-bin.sh) on engine

### Desktop (`192.168.10.31`, WSL2 agent)

- **GPU:** NVIDIA GeForce RTX 3090 (WSL passthrough; driver via Windows)
- **Setup:** [desktop-wsl-setup.sh](../k8s/gpu/desktop-wsl-setup.sh) — toolkit, containerd v3 drop-in, `no-cgroups` for WSL
- **Labels:** `gpu=nvidia`, `workload=burst`
- **SSH:** WSL port **2222**; homelab key in `authorized_keys`. From blackpearl: `ssh -p 2222 -i ~/.ssh/homelab s4il0r@192.168.10.31`
- **Firewall:** run [windows-firewall-homelab-desktop-apply.ps1](../scripts/windows-firewall-homelab-desktop-apply.ps1) on the Windows host (auto-elevates; applies netsh + Hyper-V rules) (opens **9100**, **9400**, **10250**, **2222**). WSL mirrored mode requires Hyper-V rules for DCGM **9400**.
- **Verify:** `nvidia.com/gpu: 1`, DCGM pod on `desktop`, ~48 `DCGM_FI_*` metrics per exporter (same as engine)

## metrics-server / `kubectl top`

If workers show `<unknown>`, apply the k3s kubelet TLS patch in [k8s/monitoring/metrics-server-k3s-patch.md](../k8s/monitoring/metrics-server-k3s-patch.md).

## Lens (workstation only)

No cluster install. On your PC:

1. **Copy kubeconfig** from blackpearl:
   ```powershell
   scp -i .\homelab s4il0r@192.168.10.41:~/.kube/config $env:USERPROFILE\.kube\config-homelab
   ```
2. Point Lens at that file (Settings → Kubernetes → Add from kubeconfig), or:
   ```powershell
   $env:KUBECONFIG = "$env:USERPROFILE\.kube\config-homelab"
   ```
3. Install [OpenLens](https://github.com/MuhammedKalkan/OpenLens) (or Lens IDE).
4. Open the homelab cluster — you should see nodes, pods, and metrics (needs metrics-server).

Ensure your PC can reach `192.168.10.0/24` (VPN/LAN).

## Re-deploy from git

On blackpearl, clone/copy `k8s/monitoring/` and `k8s/gpu/`, then run commands in [k8s/monitoring/README.md](../k8s/monitoring/README.md) and [k8s/gpu/README.md](../k8s/gpu/README.md).

## Troubleshooting empty Grafana panels

If dashboards show **no data** but Grafana login works:

1. Confirm Prometheus pod IP is on flannel (`10.42.x`), not Podman (`10.88.x`):  
   `kubectl get pod -n monitoring prometheus-prometheus-stack-prometheus-0 -o wide`
2. On **engine**, run [scripts/homelab-engine-cni-fix.sh](../scripts/homelab-engine-cni-fix.sh) and recycle monitoring pods on engine.
3. From the Grafana pod, test:  
   `wget -qO- --timeout=5 http://prometheus-stack-prometheus.monitoring.svc:9090/-/healthy`
4. See [homelab-ops-audit.md](./homelab-ops-audit.md) for the full ops checklist.

Optional sibling repo pointer only: homelab-k3s may reference this path; live install is in **beelink-cleanup**.

