# engine — k3s GPU worker

Engine is the **dedicated GPU box** (not the daily driver). It joins **blackpearl** as a k3s agent for training workloads.

| Item | Value |
|------|--------|
| Host | `engine` / `192.168.10.32` (Fritz!box may list `.29` / `.40` — use the one that answers SSH) |
| User | `s4il0r` |
| Cluster | `https://192.168.10.41:6443` (blackpearl) |
| Labels | `workload=training`, `gpu=nvidia`, `machine=engine` |

## One-time: SSH keys (password once)

From your PC, copy repo to engine and run:

```powershell
scp -r C:\Users\s4il0r\Documents\Programming\beelink-cleanup s4il0r@engine:~/beelink-cleanup
ssh s4il0r@engine "bash ~/beelink-cleanup/scripts/setup-engine-access.sh"
```

Or paste `scripts/blackpearl.pub` into `~/.ssh/authorized_keys` on engine.

Verify:

```powershell
ssh -i C:\Users\s4il0r\Documents\Programming\beelink-cleanup\blackpearl s4il0r@192.168.10.41 "ssh s4il0r@192.168.10.32 hostname"
```

## Join cluster

**Option A — from blackpearl (after SSH works):**

```bash
# on blackpearl
git clone ... beelink-cleanup  # or scp scripts/
bash ~/staging/beelink-cleanup/scripts/onboard-engine-from-blackpearl.sh
```

**Option B — on engine directly:**

```bash
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.10.41:6443 K3S_TOKEN='...' sh -s - agent --node-name engine
```

Token: `sudo cat /var/lib/rancher/k3s/server/node-token` on blackpearl.

Then on blackpearl:

```bash
kubectl label node engine workload=training gpu=nvidia machine=engine --overwrite
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.0/deployments/static/nvidia-device-plugin.yml
```

## Training jobs

Schedule with `nodeSelector` / affinity for `workload=training` and request `nvidia.com/gpu`. See majico `deploy/training/` when added.

Engine has **no taint** (always welcome training). The daily PC should get `dedicated=training:NoSchedule` when you add it later.

## Ollama LLM service (host GPU)

Bare-metal Ollama on engine (not in k3s): [engine-ollama.md](engine-ollama.md) — `bash scripts/engine-ollama-deploy.sh` from this repo.
