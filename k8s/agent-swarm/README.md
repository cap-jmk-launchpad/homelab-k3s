# Agent swarm on homelab k3s

Full stack in Kubernetes (namespace `agent-swarm`):

| Component | In k8s | Node (default) |
|-----------|--------|----------------|
| **Postgres + PostgREST** | Yes | blackpearl |
| **Dashboard + async swarm** | Yes | blackpearl (or **deck** overlay) |

No host Docker Supabase required. See [db/README.md](./db/README.md).

### Dashboard URL (LAN)

Prefer the edge hostname (li-httpd on `192.168.10.33`):

- **Dashboard:** `http://agents.homelab.lan/`
- **PostgREST API:** `http://api.agents.homelab.lan/rest/v1/`

Requires `*.homelab.lan` DNS — see [docs/homelab-lan-dns.md](../../docs/homelab-lan-dns.md). NodePort fallbacks (if edge DNS works but you skip hostnames): dashboard `:30477`, API `:30421` on any k3s node.

### Raspberry Pi **deck**

- Guide: [overlays/deck/README.md](./overlays/deck/README.md)
- DB still on **blackpearl**; apps on **deck**
- Dashboard: `http://192.168.10.26:30477/`

## Deploy (blackpearl)

```bash
cd beelink-cleanup
./scripts/k8s-agent-swarm-db-secret.sh
./scripts/k8s-agent-swarm-secret.sh /path/to/li-cursor-agents/.env
./scripts/k8s-agent-swarm-apply.sh
```

## Deploy (deck apps + blackpearl db)

```bash
./scripts/k8s-agent-swarm-prepare-deck.sh
./scripts/k8s-agent-swarm-db-secret.sh
./scripts/k8s-agent-swarm-secret.sh /path/to/li-cursor-agents/.env
./scripts/k8s-agent-swarm-apply-deck.sh
```

## Verify

```bash
kubectl -n agent-swarm get pods -o wide
curl -sf http://192.168.10.41:30421/rest/v1/ -H "apikey: $(kubectl get secret agent-swarm-secrets -n agent-swarm -o jsonpath='{.data.SUPABASE_SERVICE_ROLE_KEY}' | base64 -d)" | head
curl -sf http://192.168.10.26:30477/api/health
```