# Agent swarm on Raspberry Pi **deck**

| | |
|--|--|
| Node | `deck` |
| LAN IP | `192.168.10.26` |
| Arch | `arm64` (`node:22-bookworm-slim` pulls arm64 automatically) |
| Dashboard URL | `http://192.168.10.26:30477/` |

**Database:** Supabase stays on **blackpearl** (`192.168.10.41:54321`). The Pi only runs the dashboard + async-swarm pods.

## One-time: prepare the checkout on deck

From a machine that can SSH to deck (e.g. blackpearl with `~/.ssh/homelab`):

```bash
cd beelink-cleanup
./scripts/k8s-agent-swarm-prepare-deck.sh
```

This rsyncs `li-langverse` (without `node_modules`) and runs `npm ci && npm run build` **on the Pi** so pods do not compile on every restart.

## Deploy

On **blackpearl** (or anywhere with homelab `kubectl`):

```bash
kubectl uncordon deck
cd beelink-cleanup
./scripts/k8s-agent-swarm-secret.sh /path/to/li-cursor-agents/.env
./scripts/k8s-agent-swarm-apply-deck.sh
```

## Verify

```bash
kubectl -n agent-swarm get pods -o wide
curl -sf http://192.168.10.26:30477/api/health
```

## If the Pi runs out of memory

1. Scale swarm off: `kubectl -n agent-swarm scale deployment/agents-async-swarm --replicas=0`
2. Or move swarm back to blackpearl: use `kubectl apply -k k8s/agent-swarm/` (base overlay) for async-swarm only.

Ensure Supabase on blackpearl allows connections from deck (LAN); REST is on `:54321`.
