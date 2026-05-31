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

- **Logs:** container stdout/stderr from `/var/log/pods` on every node, with Kubernetes metadata (`k8s.namespace.name`, `k8s.pod.name`, `k8s.container.name`, `k8s.node.name`, …).

- **Metrics:** host metrics, kubelet metrics, cluster-level metrics (otelDeployment on blackpearl).

- **Traces:** not auto-instrumented; send OTLP from instrumented apps to `signoz-otel-collector.signoz.svc:4317`.

**desktop (WSL worker):** k8s-infra log agents may fail on WSL mount propagation; use kubectl logs for desktop pods if SigNoz has gaps.

## Loki removed (2026-05-31)

Homelab logs use **k8s-infra → SigNoz** only. Loki, Alloy, the Grafana Loki datasource, and the Homelab Pod Logs dashboard were removed from the cluster and git.

### Optional: Grafana Alloy → OTLP (not deployed)

To avoid two log collectors, you can extend [alloy-daemonset.yaml](../k8s/monitoring/alloy-daemonset.yaml) with an `otelcol.exporter.otlp` to `signoz-otel-collector` and set `presets.logsCollection.enabled: false` in k8s-infra. That is not enabled by default in this repo.

## Storage

| PVC | Class | Size | Node |

|-----|-------|------|------|

| ClickHouse data | `local-path` | 50Gi | blackpearl (k3s local-path) |

| SigNoz SQLite/state | `local-path` | 2Gi | blackpearl |

| PostgreSQL | `local-path` | 8Gi | blackpearl |

Engine HDD: **`/srv/homelab/prometheus`** remains for Prometheus TSDB. Leftover **`/srv/homelab/loki`** on **engine** was deleted 2026-05-31 (~17MiB reclaimed; `df` on `/` unchanged at ~49% used). SigNoz data lives on blackpearl PVCs only.

## Resource notes (homelab sizing)

Official capacity docs target large clusters (multi-core ClickHouse, many collector replicas). This install uses **single replicas** and reduced requests suitable for a small k3s homelab (~8–16Gi RAM free on blackpearl recommended).

- **arm64:** SigNoz backend is excluded from Pis by nodeSelector; otel agent images are multi-arch. Very old arm CPUs without AVX2 may need ClickHouse `allow_simdjson=0` (see SigNoz issue #10819) — unlikely on blackpearl x86.

- **Retention:** tune in SigNoz UI / ClickHouse TTL later; default chart retention applies until customized.

## Application instrumentation

Point SDKs or collectors at:

- gRPC: `signoz-otel-collector.signoz.svc.cluster.local:4317`

- HTTP: `http://signoz-otel-collector.signoz.svc.cluster.local:4318`

From a pod in the cluster, set `OTEL_EXPORTER_OTLP_ENDPOINT` accordingly.

## Dashboards (recommended — no custom import)

For homelab Kubernetes logs, **use built-in SigNoz views**; k8s-infra already attaches `k8s.namespace.name`, `k8s.pod.name`, and related attributes. There is no dedicated "homelab logs" JSON in this repo on purpose (less maintenance than a custom dashboard).

| What you want | Where | URL / action |
|---------------|-------|--------------|
| Tail / search pod logs | **Logs Explorer** | [http://192.168.10.41:30301/logs](http://192.168.10.41:30301/logs) |
| Pod / node CPU, memory, K8s infra | **Infrastructure monitoring** | UI: **Infrastructure** → **Kubernetes** (metrics from k8s-infra) |
| PromQL-style charts you build yourself | **Dashboards** | [http://192.168.10.41:30301/dashboard](http://192.168.10.41:30301/dashboard) |

### Homelab namespaces (Logs Explorer)

1. Open **Logs Explorer**.
2. Add a filter on **`k8s.namespace.name`** (one of `agent-swarm`, `training`, `majico-staging`), or use the attribute sidebar after a broad query.
3. **Errors:** add a line filter such as `error` (case-insensitive) or match your apps' log level field if present.
4. **Top noisy pods:** group or order by **`k8s.pod.name`** in the log table (or add a count panel under **Dashboards** only if you outgrow Explorer).

Optional: **Save view** in Logs Explorer for each namespace so you get one-click filters later.

### Community dashboard templates (optional)

SigNoz publishes importable JSON for databases, APM, etc. — not a first-class "K8s pod logs" board (logs belong in **Logs Explorer**).

- Template catalog: [Dashboard templates overview](https://signoz.io/docs/dashboards/dashboard-templates/overview/)
- GitHub repo: [SigNoz/dashboards](https://github.com/SigNoz/dashboards)
- Import path in UI: **Dashboards** → **+ New dashboard** → **Import** (paste JSON)

k8s-infra setup reference: [K8s infra metrics and logs](https://signoz.io/docs/infrastructure-monitoring/user-guides/k8s-infra-metrics-and-logs/)

## Related docs

- [homelab-monitoring.md](./homelab-monitoring.md) — Prometheus, Grafana, GPU

- [homelab-logging.md](./homelab-logging.md) — Loki + Alloy

