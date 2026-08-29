# Cluster watchdog — unified keep-up service

A single systemd timer on **blackpearl** that monitors the whole k3s cluster + edge and
keeps deployed services up. It replaces the previously-overlapping watchdogs and
consolidates their duties into one place.

## What replaced

| Before (multiple) | Now (one) |
|-------------------|-----------|
| `li-httpd-edge-watchdog.timer` → `edge-watchdog.sh` (probe nginx :443 + li-httpd; heal) | `cluster-watchdog.timer` → `cluster-watchdog.sh heal_edge` |
| `gitlab-edge-watchdog.timer` → `gitlab-edge-watchdog.sh` (probe GitLab :443; heal upstream for engine DHCP; restart gitlab-0; tunnel) | folded into `cluster-watchdog.sh` (edge heal + `gitlab-edge-watchdog.sh` internal healer) |
| `supabase-backup-prune`, `librebase-supabase-backup-prune`, `agentic-book-supabase-backup-prune` CronJobs (3× identical 30-day prune) | `cluster-watchdog.sh rotate_backups` triggers them on-demand + adds **GitLab** backup rotation (was missing) |
| `engine-disk-maintenance` (external repo, 6h) — containerd images + engine disk | complements cluster-watchdog `prune_images` (cluster-wide image GC is on the kubelet `ImageGC` defaults) |

Prometheus/Grafana + SigNoz remain the **visibility** layer (metrics/logs/alerts). The
cluster watchdog is the **healing** layer — the only one that restarts things and reclaims
disk on a schedule.

## Duties (the four you asked for)

1. **Keep portfolio up** — probes the portfolio backend on `127.0.0.1:30585` and the WAN
   `https://www.julianmkleber.com/health`. If the backend is down it discovers the Service
   behind NodePort `30585` (via `kubectl`) and restarts its pods; if the WAN fails while the
   backend is up it re-applies the edge config (`homelab-edge-policy-check.sh --fix`) and
   re-loads nginx.
2. **Prune stale containers** — every run: deletes `Failed`/`Succeeded`/`Evicted` pods,
   completed `Job`s older than retention, and `Released` local-path PVs (plus the engine
   host dir). Container-image GC runs every 6 h on blackpearl + engine via `k3s ctr`.
3. **Rotate backups** — daily: prunes GitLab backups older than 30 d (`exec gitlab-0`),
   and triggers the per-stack `*-backup-prune` CronJobs for the Supabase family. GitLab
   had **no rotation before** — this closes it.
4. **Dashboard / service health** — probes every service in
   [`services.conf`](services.conf) (source of truth for the WAN/LAN product surface).
   Any service that is **down** and does **not** belong to `agent-swarm` is restarted
   (pod recycle). `agent-swarm` services (e.g. `agents-dashboard`) are **monitor-only** —
   never restarted by the watchdog (their lifecycle is owned by the agent stack).

## Install (blackpearl)

```bash
cd /home/s4il0r/staging/homelab-k3s
sudo bash scripts/deploy-cluster-watchdog.sh
```

This installs `/usr/local/bin/cluster-watchdog.sh`, copies `services.conf` to
`/etc/cluster-watchdog/services.conf`, installs `cluster-watchdog.service` / `.timer`,
arms the timer, and **retires** `li-httpd-edge-watchdog.timer` +
`gitlab-edge-watchdog.timer`.

To also suspend the redundant per-stack backup-prune CronJobs (rotation now owned by the
watchdog):

```bash
sudo bash scripts/deploy-cluster-watchdog.sh --retire-redundant-cronjobs
```

## Runbook

```bash
journalctl -u cluster-watchdog.service -f            # live log of runs
less /var/log/cluster-watchdog.log                    # best-effort action log
sudo -u root KUBECONFIG=/home/s4il0r/.kube/config /usr/local/bin/cluster-watchdog.sh --check-only   # dry run (probes only)
sudo -u root KUBECONFIG=/home/s4il0r/.kube/config /usr/local/bin/cluster-watchdog.sh --dry-run     # alias of --check-only
sudo -u root KUBECONFIG=/home/s4il0r/.kube/config /usr/local/bin/cluster-watchdog.sh --once         # one full pass
systemctl list-timers cluster-watchdog.timer
```

### Safety

- `--check-only` and `--dry-run` are aliases; both set a flag that makes every
  mutating helper (`mut`) log `[dry-run] would: …` and perform **no** restarts,
  reloads, deletes, or prunes.
- Any **unknown argument is a hard error** (exit 2). The watchdog will never fall
  through from a typo into a live mutating run.
- Hard halt without touching systemd: `sudo touch /etc/cluster-watchdog/DISABLED`
  — the next run exits immediately and performs no mutations.

## Configuration (env overrides, set in the systemd unit)

| Var | Default | Meaning |
|-----|---------|---------|
| `CLUSTER_WATCHDOG_INVENTORY` | `/etc/cluster-watchdog/services.conf` | service inventory |
| `PROBE_TIMEOUT` / `PROBE_MAX` | 10 / 15 | curl timeouts |
| `SVC_FAIL_THRESHOLD` | 2 | consecutive failures before restarting a service pod |
| `PORTFOLIO_FAIL_THRESHOLD` | 2 | consecutive failures before restarting portfolio backend |
| `IMAGE_PRUNE_HOURS` | 6 | containerd image GC cadence |
| `BACKUP_ROTATE_HOURS` | 24 | backup rotation cadence |
| `BACKUP_RETENTION_DAYS` | 30 | backup + completed-Job retention |
| `ENGINE_NODE` | `engine` | node whose LAN IP the GitLab nginx upstream is patched to |
| `SSH_KEY` | `/home/s4il0r/.ssh/homelab` | SSH key for per-node containerd prune |

## Service inventory

Canonical list: [`k8s/monitoring/cluster-watchdog/services.conf`](services.conf).
Add a row to monitor a new product; the watchdog discovers the pod to restart by NodePort,
so no namespace needs to be hardcoded (portfolios `30585` is discovered dynamically).

## Notes

- `engine`’s LAN IP flips (`192.168.10.32` ↔ `192.168.10.40`) on DHCP. The watchdog reads
  the live `InternalIP` from the k8s API and delegates upstream normalization to the
  GitLab edge healer (prefers `127.0.0.1:30481` loopback via kube-proxy).
- The watchdog runs on **blackpearl** because it must reach kube-proxy NodePorts on the
  loopback, restart the host `li-httpd`/`nginx-gitlab-edge` units, and SSH into nodes for
  image GC. If blackpearl is down the whole cluster control plane is down anyway.
