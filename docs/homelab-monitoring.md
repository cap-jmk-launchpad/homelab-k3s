# Homelab k3s monitoring

Cluster control plane: **blackpearl** (`192.168.10.41` SSH, node IP often `192.168.10.33`).

## What is installed

| Component | Namespace | Notes |
|-----------|-----------|-------|
| metrics-server | `kube-system` | k3s default; `kubectl top` |
| kube-prometheus-stack | `monitoring` | Prometheus + Grafana + node-exporter |
| DCGM exporter | `monitoring` | DaemonSet on `engine` (`gpu=nvidia`) |

**Prometheus** (TSDB) runs on **engine** with persistent storage on the engine HDD. **Grafana**, **Alertmanager**, and the **prometheus-operator** stay on **blackpearl** (`kubernetes.io/hostname=blackpearl`). **node-exporter** runs on all nodes (arm64 Pis included).

`majico-staging` is untouched.

Manifests: [k8s/monitoring/](../k8s/monitoring/).

## Grafana (LAN)

- **URL:** `http://192.168.10.41:30300` (or `http://192.168.10.33:30300` via node IP)
- **Port:** NodePort `30300`
- **User:** `admin`
- **Password:** set at Helm deploy (`--set grafana.adminPassword=...`). Not stored in git. On blackpearl: `cat /tmp/monitoring-secrets.env` (if still present).

Default dashboards: Kubernetes / Node Exporter / Prometheus. GPU: search Grafana for DCGM or add a DCGM dashboard (UID varies by exporter version).

## Prometheus

In-cluster: `http://prometheus-stack-prometheus.monitoring.svc:9090` (ClusterIP). Use Grafana Explore or port-forward for ad-hoc queries.

**Retention:** 180 days (6 months). TSDB size capped at 200GB (`retentionSize`); time-based cap is `retention: 180d` in [kube-prometheus-stack-values.yaml](../k8s/monitoring/kube-prometheus-stack-values.yaml).

**Storage (engine HDD):**

| Item | Value |
|------|--------|
| Node | `engine` (`192.168.10.32`) |
| Disk | `sda2` → `/` (465G HDD; NVMe LUKS is separate and unused) |
| Host path | `/srv/homelab/prometheus` |
| PV / StorageClass | `prometheus-engine-tsdb` / `prometheus-engine` ([prometheus-engine-pv.yaml](../k8s/monitoring/prometheus-engine-pv.yaml)) |
| Free space (typical) | ~320G on `/` — headroom for ~200G TSDB cap plus OS/training data |

Prepare on engine (once):

```bash
sudo mkdir -p /srv/homelab/prometheus
sudo chown 65534:65534 /srv/homelab/prometheus
```

Older samples are dropped automatically when retention or `retentionSize` is exceeded.

## GPU metrics (engine)

`dcgm-exporter` DaemonSet selects `gpu=nvidia` (engine). ServiceMonitor label `release: prometheus-stack` so Prometheus scrapes port `9400`.

Verify on blackpearl:

```bash
kubectl get pods -n monitoring -l app=dcgm-exporter -o wide
kubectl run curl-dcgm --rm -it --restart=Never -n monitoring --image=curlimages/curl -- \
  curl -s http://dcgm-exporter.monitoring.svc:9400/metrics | head
```

If DCGM logs show NVML errors, confirm NVIDIA drivers and `/dev/nvidia` on **engine** (device plugin alone does not replace host drivers).

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

On blackpearl, clone/copy `k8s/monitoring/` and run commands in [k8s/monitoring/README.md](../k8s/monitoring/README.md).

Optional sibling repo pointer only: homelab-k3s may reference this path; live install is in **beelink-cleanup**.
