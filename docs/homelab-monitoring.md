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

**Retention:** **180 days** (6 months). TSDB size capped at 200GB (`retentionSize`); time-based cap is `retention: 180d` in [kube-prometheus-stack-values.yaml](../k8s/monitoring/kube-prometheus-stack-values.yaml).

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
sudo chown -R 1000:2000 /srv/homelab/prometheus
```

Samples older than 180 days are dropped automatically. Older samples may also be dropped when `retentionSize` (200GB) is exceeded.

## GPU metrics (engine)

`dcgm-exporter` DaemonSet selects `gpu=nvidia` (engine). ServiceMonitor label `release: prometheus-stack` so Prometheus scrapes port `9400`.

Verify on blackpearl:

```bash
kubectl get pods -n monitoring -l app=dcgm-exporter -o wide
kubectl run curl-dcgm --rm -it --restart=Never -n monitoring --image=curlimages/curl -- \
  curl -s http://dcgm-exporter.monitoring.svc:9400/metrics | head
```

If DCGM logs show NVML errors, confirm NVIDIA drivers and `/dev/nvidia` on **engine** (device plugin alone does not replace host drivers).

## Cluster memory (Grafana / Prometheus)

**Node capacity** (from `kubectl get nodes`; 5-node homelab):

| Node | RAM (approx.) | LAN IP |
|------|----------------|--------|
| anch0r | 1.8 GiB | 192.168.10.22 |
| deck | 7.6 GiB | 192.168.10.26 |
| blackpearl | 12.6 GiB | 192.168.10.33 |
| desktop (WSL) | 31 GiB | 192.168.10.31 |
| engine | 62 GiB | 192.168.10.32 |
| **Total** | **~115 GiB** | |

Prometheus scrapes **node-exporter** on port `9100` (DaemonSet on every node). Use **cluster-wide** PromQL so Grafana shows all nodes, not a single instance:

```promql
# Total installed RAM (GiB)
sum(node_memory_MemTotal_bytes) / 1024 / 1024 / 1024

# Available RAM (GiB)
sum(node_memory_MemAvailable_bytes) / 1024 / 1024 / 1024

# Used % (cluster)
100 * (1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes))
```

In **Explore** or a custom panel: `count(node_memory_MemTotal_bytes)` should equal the number of healthy exporters (4–5). If it is `1` or `2`, only blackpearl/engine were reachable — see worker firewall below.

Default **Node Exporter Full** dashboards filter by `instance`; pick **All** or use the queries above for homelab totals.

### Worker firewall (required for Pi nodes)

Scrapes and `kubectl top` call worker **LAN IPs** (`192.168.10.x`) on ports **9100** (node-exporter) and **10250** (kubelet). Default **ufw** on Pis blocks these from the LAN; symptoms:

- Prometheus: `count(node_memory_MemTotal_bytes)` ≪ node count; targets `context deadline exceeded`
- `kubectl top`: `<unknown>` on workers while control-plane/engine work

**One-time (per worker):** run [scripts/homelab-open-monitoring-ports.sh](../scripts/homelab-open-monitoring-ports.sh) as root, or apply the optional [homelab-worker-firewall-ds.yaml](../k8s/monitoring/homelab-worker-firewall-ds.yaml) then delete it:

```bash
kubectl apply -f k8s/monitoring/homelab-worker-firewall-ds.yaml
# after all pods log configured-ufw / configured-iptables:
kubectl delete -f k8s/monitoring/homelab-worker-firewall-ds.yaml
```

Nodes without `ufw` (e.g. **anch0r**) still need `iptables` INPUT rules for `192.168.10.0/24` → `9100`, `10250` (the DaemonSet adds these when `iptables` exists).

### desktop (WSL2)

- **node-exporter:** set `prometheus-node-exporter.hostRootFsMount.enabled: false` in Helm values (WSL cannot mount `/` with rshared). Pod should be `Running` on `desktop`.
- **LAN scrape / kubelet:** WSL often blocks inbound from other LAN hosts. Allow TCP **9100** and **10250** on the Windows host for `192.168.10.0/24`, or accept missing desktop metrics in cluster sums until fixed.

## metrics-server / `kubectl top`

If workers show `<unknown>`, apply the k3s kubelet TLS patch in [k8s/monitoring/metrics-server-k3s-patch.md](../k8s/monitoring/metrics-server-k3s-patch.md), then ensure worker **firewall** allows **10250** from the LAN (see above).

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
