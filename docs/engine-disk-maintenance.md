# Engine disk maintenance (6h)

Automated relief for **engine** node disk pressure: Released local-path PVs, stale pods, containerd image layers, AIMD demo scratch, and idle goal-worker Deployments.

## Schedule

| Resource | Schedule | Status |
|----------|----------|--------|
| **CronJob** `engine-disk-maintenance` | `0 */6 * * *` UTC | **active** |
| CronJob `engine-worker-disk-cleanup` | `0 */6 * * *` UTC | **suspended** (superseded) |

## What each run does

1. **Released PVs** — delete `local-path` PVs in `Released` phase with node affinity on `engine`; remove matching dirs under `/var/lib/rancher/k3s/storage/` (privileged initContainer).
2. **Stale pods** — delete `Failed`, `Succeeded`, and `Evicted` pods on `engine` (AIMD evicted pods older than 24h).
3. **Containerd prune** — `ctr images prune` + `content prune` on the engine host (same pattern as `job-engine-disk-prune.yaml`).
4. **AIMD PVC scratch** — on `li-world-studio-aimd-demo-workspace`: wipe demo-recorder frame trees when no AIMD pods are Running; age-prune hero frames (`KEEP_DAYS=7`).
5. **Idle scale-down** — scale documented completed/idle goal Deployments to `0` (e.g. `li-ph-sci-gap-close-phase2`, `li-ph-sci-electrochemistry`). **Skips** `li-ph-sci-full-parity` while it has replicas or a Running pod; skips Deployments with `li-langverse.io/goal-protect-from-headroom: "1"`.

Break-glass one-shots (unchanged):

- `job-engine-disk-prune.yaml` — host containerd only
- `job-aimd-pvc-cleanup.yaml` — aggressive AIMD PVC wipe

## Apply

```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-homelab"
kubectl apply -f li-cursor-agents/deploy/k8s/engine/rbac-engine-disk-maintenance.yaml
kubectl apply -f li-cursor-agents/deploy/k8s/engine/cronjob-engine-disk-maintenance.yaml
kubectl apply -f li-cursor-agents/deploy/k8s/engine/cronjob-engine-worker-disk-cleanup.yaml
```

## Manual run

```bash
export KUBECONFIG=$HOME/.kube/config-homelab
bash li-cursor-agents/scripts/engine-disk-maintenance.sh
```

Dry run: `DRY_RUN=1 bash li-cursor-agents/scripts/engine-disk-maintenance.sh`

Trigger CronJob once:

```bash
kubectl -n li-swarm create job --from=cronjob/engine-disk-maintenance engine-disk-maintenance-manual-$(date -u +%Y%m%d%H%M%S)
```

## Verify

```bash
kubectl -n li-swarm get cronjob engine-disk-maintenance
kubectl -n li-swarm get jobs -l app=engine-disk-maintenance --sort-by=.metadata.creationTimestamp
kubectl describe node engine | grep -i disk
kubectl get pv | grep Released || echo "no Released PVs"
```

Agent loop (6h verification tick): see `li-cursor-agents/deploy/k8s/engine/README.md`.
