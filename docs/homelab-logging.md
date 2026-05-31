# Homelab logging (SigNoz)

Container logs are collected by **SigNoz k8s-infra** (OpenTelemetry agents on every node) and stored in SigNoz (ClickHouse), not Loki.

- **Docs:** [homelab-signoz.md](./homelab-signoz.md) — UI, OTLP endpoints, log search
- **Deploy:** `bash scripts/homelab-deploy-signoz.sh`
- **Metrics / Grafana dashboards:** [homelab-monitoring.md](./homelab-monitoring.md)

## kubectl fallback

When the SigNoz UI is unavailable or you need a quick local tail:

```bash
kubectl logs -n <namespace> <pod> -c <container> -f
kubectl logs -n <namespace> <pod> --all-containers=true --tail=200
```

Loki and Grafana Alloy were removed in favor of SigNoz (2026-05-31).
