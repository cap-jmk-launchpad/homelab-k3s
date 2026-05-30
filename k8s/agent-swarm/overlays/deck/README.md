# Agent swarm on Raspberry Pi **deck**

| | |
|--|--|
| Apps (dashboard + swarm) | **deck** `192.168.10.26` |
| Database (Postgres + PostgREST) | **blackpearl** (in-cluster) |
| Dashboard | `http://192.168.10.26:30477/` |

```bash
./scripts/k8s-agent-swarm-prepare-deck.sh
./scripts/k8s-agent-swarm-db-secret.sh
./scripts/k8s-agent-swarm-secret.sh /path/to/li-cursor-agents/.env
./scripts/k8s-agent-swarm-apply-deck.sh
```