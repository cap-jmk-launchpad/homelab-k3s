# Homelab ops audit

Operational checklist for the k3s homelab after security hardening. Run from **blackpearl** (`s4il0r@192.168.10.41`) unless noted.

**Last verified:** 2026-05-30

## Quick checklist

| Check | Command / URL | Expected |
|-------|----------------|----------|
| All nodes Ready | `kubectl get nodes` | 5× `Ready` |
| Staging app (LAN) | `curl -s -o /dev/null -w '%{http_code}\n' http://192.168.10.41:30080/` | `200` |
| Staging Kong (LAN) | `curl -s -o /dev/null -w '%{http_code}\n' http://192.168.10.41:30000/` | `200` or `404` (root path) |
| Prometheus targets | `bash scripts/homelab-prom-targets-summary.sh` on blackpearl | Most UP; desktop may be DOWN until Windows firewall |
| Grafana datasource | Grafana → Explore → `up` | Data; or proxy API `count(up)` → success |
| Grafana panels | http://192.168.10.41:30300 | CPU/RAM/GPU panels populate |
| `kubectl top nodes` | `kubectl top nodes` | 4 nodes with metrics; `desktop` often `<unknown>` until :9100/:10250 open on Windows |
| Lens / kubeconfig | Copy `~/.kube/config` from blackpearl | Cluster visible |
| UFW LAN-only | `sudo ufw status` on nodes | No wide-open NodePorts except documented; 9100/10250 from `192.168.10.0/24` |

## Grafana empty panels (fixed 2026-05-30)

**Root cause:** Prometheus on **engine** was on Podman CNI (`10.88.0.0/16`) instead of k3s flannel (`10.42.x`). Grafana on blackpearl could not reach the Prometheus pod or ClusterIP backend across the split networks.

**Fix:**

1. On engine: [scripts/homelab-engine-cni-fix.sh](../scripts/homelab-engine-cni-fix.sh) — disable `87-podman-bridge.conflist`, install k3s flannel into `/etc/cni/net.d/`, restart `k3s-agent`.
2. Recycle engine monitoring pods so they get `10.42.1.x` addresses.
3. Engine UFW: allow **UDP 8472** (flannel), `default allow routed`, and flannel/cni rules in `before.rules` — [scripts/homelab-security-ufw-engine-k3s.sh](../scripts/homelab-security-ufw-engine-k3s.sh) (see [homelab-security-audit.md](./homelab-security-audit.md)).

**Verify:**

```bash
# From blackpearl — Prometheus pod must be 10.42.1.x, not 10.88.x
kubectl get pod -n monitoring prometheus-prometheus-stack-prometheus-0 -o wide

# Grafana pod → in-cluster Prometheus
kubectl exec -n monitoring deploy/prometheus-stack-grafana -c grafana -- \
  wget -qO- --timeout=5 http://prometheus-stack-prometheus.monitoring.svc:9090/-/healthy
```

## Prometheus target health

```bash
# On blackpearl (uses curl to Prometheus pod IP)
PROM_URL=http://10.42.1.22:9090 bash /path/to/homelab-prom-targets-summary.sh
```

Typical result after fix: **~26 UP / ~5 DOWN** (DOWN targets are usually **desktop** `192.168.10.31` — node-exporter/kubelet blocked from LAN until [windows-firewall-homelab-desktop-apply.ps1](../scripts/windows-firewall-homelab-desktop-apply.ps1) is run elevated on the Windows host).

Sample PromQL (2026-05-30):

| Query | Result |
|-------|--------|
| `up` | ~34 series |
| `count(node_memory_MemTotal_bytes)` | `4` |
| `count(DCGM_FI_DEV_GPU_UTIL)` | `2` (engine + desktop GPU exporters) |

## Security vs monitoring

- **Prometheus** scrapes node IPs on **9100** / **10250** from the LAN; UFW on workers must allow `192.168.10.0/24` — not `0.0.0.0/0`.
- **Grafana** uses in-cluster URL `http://prometheus-stack-prometheus.monitoring.svc:9090` (no public Prometheus NodePort required).
- **NetworkPolicies** in `majico-staging` do not apply to `monitoring`; they must not block flannel/kubelet paths on workers.
- **Engine:** keep Podman CNI config out of `/etc/cni/net.d/` so k3s pods stay on flannel.

## Related docs

- [homelab-monitoring.md](./homelab-monitoring.md) — deploy, dashboards, GPU
- [homelab-security-audit.md](./homelab-security-audit.md) — UFW, NodePorts, findings
- [desktop-k3s-worker.md](./desktop-k3s-worker.md) — desktop metrics firewall
