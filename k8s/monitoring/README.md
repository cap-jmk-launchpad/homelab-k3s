# Homelab k3s monitoring

Prometheus + Grafana (kube-prometheus-stack), node-exporter on all nodes, DCGM exporter on `engine` (GPU).

## Install / upgrade

On **blackpearl** (control plane), with Helm 3:

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Set a strong password at deploy time (not stored in git)
helm upgrade --install prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f kube-prometheus-stack-values.yaml \
  --set grafana.adminPassword='YOUR_PASSWORD'

kubectl apply -f prometheus-engine-pv.yaml
kubectl apply -f ../gpu/nvidia-runtimeclass.yaml
kubectl apply -f ../gpu/nvidia-device-plugin.yaml
kubectl apply -f dcgm-exporter.yaml
```

## metrics-server

Uses k3s default in `kube-system`. See [metrics-server-k3s-patch.md](./metrics-server-k3s-patch.md) if `kubectl top` shows `<unknown>` on workers.

## Files

| File | Purpose |
|------|---------|
| `kube-prometheus-stack-values.yaml` | Helm values: Grafana on blackpearl, Prometheus TSDB on engine |
| `prometheus-engine-pv.yaml` | hostPath PV + StorageClass for engine HDD |
| `dcgm-exporter.yaml` | GPU DaemonSet + ServiceMonitor on `engine` |
| `engine-homelab-fs-exporter.yaml` | Engine-only node-exporter on `:9101` for `/srv/homelab/*` (WSL-safe) |
| `desktop-node-exporter-wsl.yaml` | Desktop WSL node-exporter via `/proc/1/root` (no mount propagation) |
| `metrics-server-k3s-patch.md` | Optional kubelet TLS patch |
| `metrics-server-patch.json` | JSON patch for `--kubelet-insecure-tls` |
| `metrics-server-pin-control-plane.yaml` | Schedule metrics-server on blackpearl |
| `homelab-worker-firewall-ds.yaml` | Optional: open ufw/iptables for 9100/10250 on workers |
| `homelab-cluster-resources-dashboard.json` | Cluster memory, CPU, GPU, and physical disk (node-exporter) |
| `homelab-gpu-dashboard.json` | DCGM GPU metrics per node |

**Node colors** (fixed across all panels): blackpearl blue, engine green, desktop orange, deck purple, anch0r yellow. Re-apply after dashboard edits: `python3 scripts/patch-grafana-node-colors.py`.

Docs: [../../docs/homelab-monitoring.md](../../docs/homelab-monitoring.md)



## Grafana dashboards (sidecar)

```bash
bash ../../scripts/homelab-deploy-dashboards.sh
```

ConfigMaps need label `grafana_dashboard=1` in `monitoring` namespace.
