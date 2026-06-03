# Homelab edge ingress (LIS / li-httpd)

**LIS** (`li/lis`) supervises **li-httpd** (`li/lic`) on **blackpearl**: native Li edge on `:80`, routing by `Host` to k3s **NodePort** backends on loopback. No Caddy, nginx, Traefik, or in-cluster ingress controllers.

| Layer | Component |
|-------|-----------|
| k3s | `--disable traefik` at install ([docs/k3s-server.md](../../docs/k3s-server.md)) |
| Edge | `li-httpd` + TOML ([homelab.httpd.toml](./homelab.httpd.toml)) |
| Validate | `lis http validate` or `lic` `httpd_config.py` + [merge-httpd-config.py](./merge-httpd-config.py) |
| Flatten | `lic/scripts/flatten-httpd-config.py` → `homelab.runtime.conf` |
| Backends | NodePort → `127.0.0.1:<port>` |

## Topology

```
LAN :80
   │
   ▼
li-httpd (blackpearl)
   ├─ staging.majico.xyz → :30080 (majico-app)
   ├─ api.staging.majico.xyz → :30000 (supabase-kong)
   ├─ grafana.homelab.lan → :30300
   ├─ signoz.homelab.lan → :30301
   ├─ agents.homelab.lan → :30477
   ├─ api.agents.homelab.lan → :30421
   ├─ li-swarm.homelab.lan → :30478
   └─ search.klaut.pro → :30479 (SearXNG)
```

Majico routes: `majico.xyz/deploy/staging/edge/majico-staging.httpd.toml`. This repo adds homelab services; [merge-httpd-config.py](./merge-httpd-config.py) combines both at apply time.

## Prerequisites (blackpearl)

| Path | Purpose |
|------|---------|
| `~/staging/lic` | li-httpd C runtime, flatten script, `build-li-httpd.sh` |
| `~/staging/lis` | optional `lis http validate` oracle |
| `~/staging/majico.xyz` | majico staging TOML |
| `~/staging/beelink-cleanup` | this repo (edge TOML + scripts) |

**Build li-httpd** (after updating `lic` — homelab needs ≥32 upstream peers, ≥128 routes):

```bash
bash ~/staging/majico.xyz/deploy/staging/scripts/build-li-httpd.sh
# or: bash ~/staging/lic/scripts/build-li-httpd.sh  # when added to lic
```

## DNS (LAN)

Point at `192.168.10.41` (Fritz!box or `/etc/hosts`):

| Host |
|------|
| `grafana.homelab.lan`, `signoz.homelab.lan`, `agents.homelab.lan` |
| `api.agents.homelab.lan`, `li-swarm.homelab.lan` |
| `staging.majico.xyz`, `api.staging.majico.xyz` |

Public (WAN DNS, not LAN-only): `search.klaut.pro` — see [k8s/searxng/README.md](../searxng/README.md).

## Apply

```bash
rsync -avz -e "ssh -i beelink" k8s/edge/ scripts/edge-lis-*.sh \
  s4il0r@blackpearl:~/staging/beelink-cleanup/

ssh -i beelink s4il0r@blackpearl
cd ~/staging/beelink-cleanup
bash scripts/edge-lis-validate.sh
sudo bash scripts/edge-lis-apply.sh --install-systemd
```

Reload after TOML edits: `sudo bash scripts/edge-lis-apply.sh`

## Validate

```bash
curl -H 'Host: grafana.homelab.lan' http://127.0.0.1/health    # ok
curl -H 'Host: staging.majico.xyz' http://127.0.0.1/health   # ok
curl http://127.0.0.1:30300/login                            # Grafana NodePort
```

## lic limits (homelab)

Runtime caps in `lic/runtime/li_rt_net.c` (raised for homelab edge):

| Constant | Value | Purpose |
|----------|-------|---------|
| `HTTPD_MAX_ROUTES` | 128 | host/path rules across all vhosts |
| `HTTPD_MAX_UPSTREAM_PEERS` | 32 | distinct NodePort backends |

Rebuild `li-httpd` on blackpearl after pulling lic changes.

## Related

- [docs/edge-ingress.md](../../docs/edge-ingress.md)
- [docs/k3s-server.md](../../docs/k3s-server.md)
- majico.xyz `deploy/staging/docs/blackpearl-k8s-lis.md`

## TLS (:443)

Native li-httpd TLS uses a **second process** on port 443 (`li-httpd-homelab-tls.service`).

1. Merged HTTP TOML -> `gen-https-overlay.py` -> `homelab.https.httpd.toml`
2. `lic/scripts/setup-tls-httpd.py` writes dev certs under `/var/lib/li-httpd/tls/homelab`
3. Flatten -> `/run/li-httpd/homelab.tls.runtime.conf`

Test:

```bash
curl -k -H 'Host: grafana.homelab.lan' https://127.0.0.1/health
```

Requires **lic** with pure-li-https merged (PR #699+). Rebuild `li-httpd` after `git pull` on blackpearl.
