# Homelab k3s logging (Loki + Alloy)

Centralized container logs for all workloads. Every pod's **stdout/stderr** is collected cluster-wide and searchable in Grafana by **namespace → pod → container**.

## What is installed

| Component | Namespace | Notes |
|-----------|-----------|-------|
| Loki (SingleBinary) | `monitoring` | TSDB + chunks on **engine** HDD (`/srv/homelab/loki`, 100Gi PVC) |
| Grafana Alloy | `monitoring` | DaemonSet on **all nodes** (control plane, engine, desktop, Pis) |
| Loki datasource | Grafana (kube-prometheus-stack) | uid `loki`, in-cluster `http://loki.monitoring.svc:3100` |

Metrics stay on Prometheus; logs go to Loki. Grafana on **blackpearl** NodePort `:30300` queries both.

Manifests: [k8s/monitoring/](../k8s/monitoring/). Metrics docs: [homelab-monitoring.md](./homelab-monitoring.md).

## Deploy

On **blackpearl** (control plane), from a clone of this repo:

```bash
# 1. Prepare engine host path (once, on engine)
ssh engine 'sudo mkdir -p /srv/homelab/loki && sudo chown -R 10001:10001 /srv/homelab/loki'

# 2. Loki PV + Helm + Alloy
bash scripts/homelab-deploy-logging.sh

# 3. Grafana: Loki datasource + logs dashboard (Helm upgrade if stack already running)
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f k8s/monitoring/kube-prometheus-stack-values.yaml \
  --reuse-values

bash scripts/homelab-deploy-dashboards.sh
```

Verify:

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=loki
kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy -o wide
kubectl get pv loki-engine-data
```

Alloy should show one pod per node. Loki should be `Running` on `engine`.

## Explore logs per pod in Grafana

**URL:** `http://192.168.10.41:30300` (same Grafana as metrics).

### Quick path: Homelab Pod Logs dashboard

- **Dashboard:** `http://192.168.10.41:30300/d/homelab-pod-logs/homelab-pod-logs`
- **Variables (top):** `namespace` → `pod` → `container`
- Workflow: pick namespace (e.g. `agent-swarm`) → pick pod → optionally narrow container → read the main log panel
- Fixed rows at the bottom stream all logs for `agent-swarm`, `training`, and `majico-staging`

### Explore (ad-hoc LogQL)

1. **Explore** (compass icon) → datasource **Loki**
2. **Label browser** (builder): select `namespace`, then `pod`, then `container`
3. Or switch to **Code** mode and paste LogQL (examples below)
4. **Live** toggle (top right) for tailing new lines (like `kubectl logs -f`)

### Labels available

Alloy attaches these Loki labels on every log line:

| Label | Source | Example |
|-------|--------|---------|
| `cluster` | static | `homelab` |
| `namespace` | pod metadata | `agent-swarm` |
| `pod` | pod name | `async-swarm-7d4f8b-abc12` |
| `container` | container name | `async-swarm` |
| `node` | scheduling node | `engine`, `blackpearl`, `deck` |
| `app` | pod label `app` or `app.kubernetes.io/name` | `async-swarm` |

Filter with label matchers: `{namespace="training", pod="gpu-smoke-xxxxx", container="pytorch"}`.

## LogQL examples

**Single pod (all containers):**

```logql
{namespace="agent-swarm", pod="async-swarm-7d4f8b-abc12"}
```

**Single container:**

```logql
{namespace="training", pod="gpu-smoke-abc12", container="pytorch"}
```

**All pods in a namespace:**

```logql
{namespace="majico-staging"}
```

**Errors only (regex on log line):**

```logql
{namespace="agent-swarm", pod=~"async-swarm.*"} |~ "(?i)(error|exception|fatal|panic|fail)"
```

**Exclude noisy health checks:**

```logql
{namespace="kube-system", pod=~"coredns.*"} != "health check"
```

**By node (which worker emitted the log):**

```logql
{namespace="training", node="engine"}
```

**Rate of error lines (metrics-style):**

```logql
sum by (namespace, pod) (rate({namespace=~"agent-swarm|training"} |~ "(?i)error" [5m]))
```

**Live tail in Explore:** run any stream query, enable **Live** (or set refresh to 5s on the dashboard).

## kubectl fallback

When Grafana is down or you need a quick local tail:

```bash
# List pods
kubectl get pods -n agent-swarm

# One container
kubectl logs -n agent-swarm async-swarm-7d4f8b-abc12 -c async-swarm

# All containers in pod
kubectl logs -n agent-swarm async-swarm-7d4f8b-abc12 --all-containers=true

# Follow live
kubectl logs -n training job/gpu-smoke -f

# Previous crashed instance
kubectl logs -n agent-swarm async-swarm-7d4f8b-abc12 --previous

# Since time / last N lines
kubectl logs -n majico-staging deploy/api --since=1h --tail=200
```

Loki keeps **14 days** of history; `kubectl` only sees what kubelet still has on disk (typically much shorter unless you increase node log rotation).

## Storage and retention

| Item | Value |
|------|--------|
| Node | `engine` |
| Host path | `/srv/homelab/loki` |
| PV / StorageClass | `loki-engine-data` / `loki-engine` |
| PVC size | 100Gi |
| Retention | **14 days** (`336h` in [loki-values.yaml](../k8s/monitoring/loki-values.yaml)) |
| Replication | `replication_factor: 1` (single binary) |

Compactor deletes chunks after the retention window. If disk fills, shorten retention or increase PVC.

## Troubleshooting

**No logs in Grafana**

1. `kubectl get pods -n monitoring -l app.kubernetes.io/name=alloy` — one Ready per node?
2. `kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=30` — push errors to Loki?
3. Port-forward Loki: `kubectl port-forward -n monitoring svc/loki 3100:3100` then `curl -s http://127.0.0.1:3100/ready`
4. Grafana datasource: **Connections → Data sources → Loki → Save & test**

**Loki pod pending**

- PV not bound: apply [loki-engine-pv.yaml](../k8s/monitoring/loki-engine-pv.yaml) and ensure `/srv/homelab/loki` exists on engine with uid **10001** (Loki default).

**Labels missing `app`**

- Only present when the pod has label `app` or `app.kubernetes.io/name`. Use `pod` / `container` labels always; add `app` on Deployments if you want it in Loki.

**Chart upgrade note**

- Helm chart ≥ 12.0 may rename `SingleBinary` → `Monolithic`. If upgrade fails, set `deploymentMode: Monolithic` in [loki-values.yaml](../k8s/monitoring/loki-values.yaml).

## Files

| File | Purpose |
|------|---------|
| [loki-engine-pv.yaml](../k8s/monitoring/loki-engine-pv.yaml) | hostPath PV + StorageClass on engine |
| [loki-values.yaml](../k8s/monitoring/loki-values.yaml) | Loki Helm values (SingleBinary, retention, persistence) |
| [alloy-daemonset.yaml](../k8s/monitoring/alloy-daemonset.yaml) | Log collector DaemonSet + RBAC |
| [homelab-logs-dashboard.json](../k8s/monitoring/homelab-logs-dashboard.json) | Per-pod log dashboard |
| [homelab-deploy-logging.sh](../scripts/homelab-deploy-logging.sh) | One-shot deploy script |
