# Homelab SigNoz (OTel-native observability)

[SigNoz](https://signoz.io/) provides logs, traces, and metrics in one UI with OpenTelemetry-native ingestion. It runs alongside **Prometheus + Grafana** for infra metrics; **logs** are ingested via k8s-infra (Loki was removed).

## What is installed

| Component | Namespace | Placement | Notes |

|-----------|-----------|-----------|-------|

| SigNoz (UI, query, schema) | `signoz` | **blackpearl** | NodePort **30301**, `local-path` PVCs |

| ClickHouse + Zookeeper | `signoz` | **blackpearl** | Single shard/replica; 50Gi data PVC |

| PostgreSQL (metadata) | `signoz` | **blackpearl** | 8Gi PVC |

| signoz-otel-collector | `signoz` | **blackpearl** | Receives OTLP from agents and apps |

| k8s-infra otelAgent | `signoz` | **DaemonSet on all nodes** | Pod logs, host/kubelet metrics, k8s attributes |

| k8s-infra otelDeployment | `signoz` | **blackpearl** | Cluster-level metrics |

**Not on arm64 Pis (for SigNoz backend):** ClickHouse and the UI need RAM/SSD; they are pinned to `kubernetes.io/hostname=blackpearl` via [signoz-values.yaml](../k8s/monitoring/signoz-values.yaml). **Collection agents** still run on Pis (DaemonSet) and forward OTLP to blackpearl.

**Prometheus/Grafana:** unchanged. Use Grafana for long-retention PromQL dashboards; use SigNoz for correlated logs/traces/metrics and OTel workflows.

## Local-only / no cloud

This homelab runs **SigNoz OSS self-hosted** via the official Helm chart (signoz/signoz from https://charts.signoz.io). That is **not** [SigNoz Cloud](https://signoz.io/docs/cloud/) (managed SaaS). You do not need a SigNoz Cloud account, license key, or ingest.signoz.io endpoint for this install.

| | Self-hosted OSS (this homelab) | SigNoz Cloud (SaaS) |
|---|-------------------------------|---------------------|
| Install | Helm on your cluster | Hosted by SigNoz |
| Data store | Your ClickHouse PVCs on blackpearl | SigNoz-operated backend |
| Ingestion | In-cluster signoz-otel-collector | ingest.*.signoz.cloud / region URLs |
| UI | Your NodePort :30301 | *.signoz.cloud |

**Where data lives:** logs, traces, and metrics land in **ClickHouse** on a **local-path PVC** on **blackpearl** (50Gi data volume; PostgreSQL and SigNoz state PVCs on the same class). Nothing in [signoz-values.yaml](../k8s/monitoring/signoz-values.yaml) or [signoz-k8s-infra-values.yaml](../k8s/monitoring/signoz-k8s-infra-values.yaml) points collectors at SigNoz SaaS.

**Agents (k8s-infra):** global.cloud: other and otelCollectorEndpoint must be **OTLP HTTP** (`http://signoz-otel-collector.signoz.svc.cluster.local:4318`) because the k8s-infra chart enables `presets.otlphttpExporter` by default. gRPC `:4317` without an `http://` URL causes agents to drop all logs (`unsupported protocol scheme` in agent logs).

**No egress to SigNoz SaaS** unless you later add an exporter, license integration, or browser-only links to signoz.io docs. Chart install may pull container images from public registries (Docker Hub, etc.) on upgrade; that is image delivery, not shipping your telemetry to SigNoz Cloud.

### How to verify (on blackpearl)

```bash
# Helm: OSS chart, not a cloud connector chart
helm list -n signoz

# Agents export to in-cluster collector only
kubectl get ds signoz-k8s-infra-otel-agent -n signoz -o yaml | grep OTEL_EXPORTER_OTLP_ENDPOINT
kubectl get deploy signoz-k8s-infra-otel-deployment -n signoz -o yaml | grep OTEL_EXPORTER_OTLP_ENDPOINT

# No SaaS ingest hostnames in ConfigMaps
kubectl get configmaps -n signoz -o yaml | grep -iE 'ingest\.signoz|signoz\.cloud' || echo 'OK: no cloud ingest URLs in configmaps'

# Data PVCs on local-path
kubectl get pvc -n signoz
```

Optional network check from a debug pod: `kubectl run -it --rm debug --image=busybox --restart=Never -- wget -qO- -T 2 ingest.signoz.io 2>&1` should fail or timeout if the cluster has no general internet; your telemetry path does not use that host anyway.

## Access (LAN)

| Service | URL |

|---------|-----|

| SigNoz UI | `http://192.168.10.41:30301` (or node IP `:30301`) |

| Grafana (existing) | `http://192.168.10.41:30300` |

First login: create a local admin user in the SigNoz UI (no password in git).

Optional UFW on blackpearl (LAN only, mirror Grafana):

```bash

sudo ufw allow from 192.168.10.0/24 to any port 30301 proto tcp comment 'SigNoz NodePort LAN'

```

## Deploy

On **blackpearl**, from this repo:

```bash

bash scripts/homelab-deploy-signoz.sh

```

Verify:

```bash

kubectl get pods -n signoz

kubectl get svc -n signoz signoz

curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30301/

```

## What is collected

**k8s-infra** ([signoz-k8s-infra-values.yaml](../k8s/monitoring/signoz-k8s-infra-values.yaml)):

- **Logs:** container stdout/stderr from `/var/log/pods` on every node, with Kubernetes metadata (`k8s.namespace.name`, `k8s.pod.name`, `k8s.container.name`, `k8s.node.name`, â€¦).

- **Metrics:** host metrics, kubelet metrics, cluster-level metrics (otelDeployment on blackpearl).

- **Traces:** not auto-instrumented; send OTLP from instrumented apps to `signoz-otel-collector.signoz.svc:4317`.

**desktop (WSL worker):** k8s-infra log agents may fail on WSL mount propagation; use kubectl logs for desktop pods if SigNoz has gaps.

## Loki removed (2026-05-31)

Homelab logs use **k8s-infra â†’ SigNoz** only. Loki, Alloy, the Grafana Loki datasource, and the Homelab Pod Logs dashboard were removed from the cluster and git.

### Optional: Grafana Alloy â†’ OTLP (not deployed)

To avoid two log collectors, you can extend [alloy-daemonset.yaml](../k8s/monitoring/alloy-daemonset.yaml) with an `otelcol.exporter.otlp` to `signoz-otel-collector` and set `presets.logsCollection.enabled: false` in k8s-infra. That is not enabled by default in this repo.

## Storage

| PVC | Class | Size | Node |

|-----|-------|------|------|

| ClickHouse data | `local-path` | 50Gi | blackpearl (k3s local-path) |

| SigNoz SQLite/state | `local-path` | 2Gi | blackpearl |

| PostgreSQL | `local-path` | 8Gi | blackpearl |

Engine HDD: **`/srv/homelab/prometheus`** remains for Prometheus TSDB. Leftover **`/srv/homelab/loki`** on **engine** was deleted 2026-05-31 (~17MiB reclaimed; `df` on `/` unchanged at ~49% used). SigNoz data lives on blackpearl PVCs only.

## Resource notes (homelab sizing)

Official capacity docs target large clusters (multi-core ClickHouse, many collector replicas). This install uses **single replicas** and reduced requests suitable for a small k3s homelab (~8â€“16Gi RAM free on blackpearl recommended).

- **arm64:** SigNoz backend is excluded from Pis by nodeSelector; otel agent images are multi-arch. Very old arm CPUs without AVX2 may need ClickHouse `allow_simdjson=0` (see SigNoz issue #10819) â€” unlikely on blackpearl x86.

- **Retention:** tune in SigNoz UI / ClickHouse TTL later; default chart retention applies until customized.

## Application instrumentation

Point SDKs or collectors at:

- gRPC: `signoz-otel-collector.signoz.svc.cluster.local:4317`

- HTTP: `http://signoz-otel-collector.signoz.svc.cluster.local:4318`

From a pod in the cluster, set `OTEL_EXPORTER_OTLP_ENDPOINT` accordingly.

## Dashboards (recommended â€” no custom import)

For homelab Kubernetes logs, **use built-in SigNoz views**; k8s-infra already attaches `k8s.namespace.name`, `k8s.pod.name`, and related attributes. There is no dedicated "homelab logs" JSON in this repo on purpose (less maintenance than a custom dashboard).

| What you want | Where | URL / action |
|---------------|-------|--------------|
| Tail / search pod logs | **Logs Explorer** | [http://192.168.10.41:30301/logs](http://192.168.10.41:30301/logs) |
| Pod / node CPU, memory, K8s infra | **Infrastructure monitoring** | UI: **Infrastructure** â†’ **Kubernetes** (metrics from k8s-infra) |
| PromQL-style charts you build yourself | **Dashboards** | [http://192.168.10.41:30301/dashboard](http://192.168.10.41:30301/dashboard) |

### Homelab namespaces (Logs Explorer)

1. Open **Logs Explorer**.
2. Add a filter on **`k8s.namespace.name`** (one of `agent-swarm`, `training`, `majico-staging`), or use the attribute sidebar after a broad query.
3. **Errors:** add a line filter such as `error` (case-insensitive) or match your apps' log level field if present.
4. **Top noisy pods:** group or order by **`k8s.pod.name`** in the log table (or add a count panel under **Dashboards** only if you outgrow Explorer).

Optional: **Save view** in Logs Explorer for each namespace so you get one-click filters later.

### Community dashboard templates (optional)

SigNoz publishes importable JSON for databases, APM, etc. â€” not a first-class "K8s pod logs" board (logs belong in **Logs Explorer**).

- Template catalog: [Dashboard templates overview](https://signoz.io/docs/dashboards/dashboard-templates/overview/)
- GitHub repo: [SigNoz/dashboards](https://github.com/SigNoz/dashboards)
- Import path in UI: **Dashboards** â†’ **+ New dashboard** â†’ **Import** (paste JSON)

k8s-infra setup reference: [K8s infra metrics and logs](https://signoz.io/docs/infrastructure-monitoring/user-guides/k8s-infra-metrics-and-logs/)

## Related docs

- [homelab-monitoring.md](./homelab-monitoring.md) â€” Prometheus, Grafana, GPU

- [homelab-logging.md](./homelab-logging.md) â€” historical; logs are SigNoz-only (see Loki removed above)



## Troubleshooting

### Logs Explorer empty (no data)

1. **Agent export errors** — `kubectl logs -n signoz -l app.kubernetes.io/component=otel-agent --tail=50 | grep -i unsupported`
   - **Cause:** `OTEL_EXPORTER_OTLP_ENDPOINT` missing `http://` while the chart uses the OTLP **HTTP** exporter (port **4318**).
   - **Fix:** In [signoz-k8s-infra-values.yaml](../k8s/monitoring/signoz-k8s-infra-values.yaml) set  
     `otelCollectorEndpoint: http://signoz-otel-collector.signoz.svc.cluster.local:4318`  
     then `helm upgrade --install signoz-k8s-infra signoz/k8s-infra -n signoz -f k8s/monitoring/signoz-k8s-infra-values.yaml`.

2. **ClickHouse has rows but UI empty** — widen time range; add filter `k8s.namespace.name` exists (k8s-infra adds k8s attributes).

3. **Verify ingestion:**
   ```bash
   kubectl exec -n signoz chi-signoz-clickhouse-cluster-0-0-0 -c clickhouse -- \
     clickhouse-client --query "SELECT count() FROM signoz_logs.logs_v2"
   ```

### `signoz-k8s-infra-otel-agent` CreateContainerError on `desktop` (WSL)

Kubelet error: `path "/" is mounted on "/" but it is not a shared or slave mount` — host metrics/log collection mounts host `/` as `hostfs`; WSL2 often lacks **rshared** on `/`.

**Homelab fix:** DaemonSet excludes node `desktop` via `otelAgent.affinity` (see values). Logs from workloads on other nodes still appear. To collect on desktop later, fix mount propagation on the node or run a custom agent without the `hostfs` volume.

### Agent pod not Running on a node

```bash
kubectl get pods -n signoz -l app.kubernetes.io/component=otel-agent -o wide
kubectl describe pod -n signoz <pod>
```
