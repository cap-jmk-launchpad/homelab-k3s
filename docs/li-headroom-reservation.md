# Li headroom reservation (homelab k3s)

Li workloads must not OOM the host. Reserve memory at the **kubelet** layer (node allocatable) and cap **pod requests/limits** so the scheduler and eviction logic keep a safety margin for the OS, GitLab, and the k3s control plane.

## Numeric budget (defaults)

| Node | Host role | RAM (typical) | `system-reserved` | `kube-reserved` | `eviction-hard` | Host headroom |
|------|-----------|---------------|-------------------|-----------------|-----------------|---------------|
| **engine** | GPU + GitLab + li-swarm workers | ~64 GiB | **5 GiB** | **512 MiB** | `memory.available<1Gi` | ~5.5 GiB + 1 GiB eviction floor |
| **blackpearl** | k3s server, edge (li-httpd), DNS | ~16–32 GiB | **2 GiB** | **512 MiB** | `memory.available<512Mi` | ~2.5 GiB + 512 MiB eviction floor |

After apply, confirm:

```bash
kubectl get node engine -o custom-columns=NAME:.metadata.name,CAP:.status.capacity.memory,ALLOC:.status.allocatable.memory
kubectl get node blackpearl -o custom-columns=NAME:.metadata.name,CAP:.status.capacity.memory,ALLOC:.status.allocatable.memory
```

**Allocatable** should be roughly **capacity − system-reserved − kube-reserved** (k3s also reserves for pods/eviction).

## Apply kubelet reserve (no SSH)

From a machine with homelab `kubectl`:

```bash
# engine (GitLab + training workers)
bash scripts/apply-engine-memory-reserve.sh

# blackpearl (control plane + li-lios-kernel)
bash scripts/apply-blackpearl-memory-reserve.sh
```

Both use a one-shot privileged pod on the target node that writes `/etc/rancher/k3s/config.yaml` via [k3s-write-kubelet-memory-reserve.sh](../scripts/k3s-write-kubelet-memory-reserve.sh) and restarts k3s/k3s-agent.

Override defaults:

```bash
SYSTEM_RESERVED_MEMORY=6Gi bash scripts/apply-engine-memory-reserve.sh
SYSTEM_RESERVED_MEMORY=3Gi EVICTION_HARD='memory.available<768Mi' bash scripts/apply-blackpearl-memory-reserve.sh
```

## Goal-directed workers (li-cursor-agents)

Pod-level guards live in **li-cursor-agents** `deploy/k8s/engine/`:

| Mechanism | Purpose |
|-----------|---------|
| `resources.requests/limits` | Scheduler + cgroup caps; idle GitLab mode uses **768Mi** request / **3Gi** limit (see engine README) |
| `li-langverse.io/goal-protect-from-headroom: "1"` | [free-engine-memory-for-gitlab.ps1](../../li-cursor-agents/scripts/free-engine-memory-for-gitlab.ps1) and [rebalance-engine-goal-workers.ps1](../../li-cursor-agents/scripts/rebalance-engine-goal-workers.ps1) **skip scale-down** |
| `PriorityClass` `li-goal-protected` | Higher scheduling priority than disposable demo workers |
| ConfigMap `li-goal-worker-runtime` | `NODE_OPTIONS=--max-old-space-size=2048`, `CMAKE_BUILD_PARALLEL_LEVEL=2`, `LI_SDK_MAX_CONCURRENT=1` |

**li-lios-kernel** runs on **blackpearl** (not engine) with headroom protection so GitLab idle scripts do not kill the kernel sprint.

Validate manifests locally:

```powershell
cd li-cursor-agents
.\scripts\assert-goal-worker-headroom.ps1
```

Report live node pressure:

```powershell
.\scripts\check-node-headroom.ps1
```

## Engine idle mode (GitLab RAM)

When GitLab on engine is memory-starved, scale disposable goal workers to **0** and suspend org wake cronjobs — see [gitlab-homelab.md](gitlab-homelab.md). **Do not** lower the engine **5 GiB** system reserve.

## Kernel (LiOS / lik)

Freestanding RISC-V/i686 kernels have no GPU path and no Linux-style OOM killer. Budgets are enforced in **li-os** gates (`check-resource-budget.sh`) and [performance-memory-efficiency.md](../../li-os/docs/engineering/performance-memory-efficiency.md).
