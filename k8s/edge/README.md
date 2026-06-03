# Homelab edge ingress (blackpearl)

Traffic flow for **WAN** (`*.klaut.pro`, `majico.d3bu7.com`) and **LAN** (`*.homelab.lan`).

## WAN edge (Caddy) — default for klaut.pro

| Port | Process | Scope |
|------|---------|--------|
| **80** | Caddy | HTTP + ACME; `http://search.klaut.pro` |
| **443** | Caddy | TLS (Majico manual certs + klaut LE certs) |

**Fritz!Box:** TCP **80** and **443** → **192.168.10.33** — see [docs/fritz-klaut-pro-port-forward.md](../../docs/fritz-klaut-pro-port-forward.md).

| Hostname | Backend | WAN status |
|----------|---------|------------|
| `search.klaut.pro` | `127.0.0.1:30479` (SearXNG) | **Enabled** |
| `gitlab.klaut.pro` | `127.0.0.1:30481` | Optional — uncomment in [Caddyfile](./Caddyfile) + [homelab.httpd.toml](./homelab.httpd.toml) |
| `deps.klaut.pro` | `127.0.0.1:30482` | Optional |
| `cwe.klaut.pro` | `127.0.0.1:30483` | Optional |
| `majico.d3bu7.com`, `api.majico.d3bu7.com`, `supabase.majico.d3bu7.com` | Majico NodePorts | Enabled (manual TLS under `/etc/caddy/certs/`) |

**Internal-only** (no `*.klaut.pro` route): `grafana.homelab.lan`, `signoz.homelab.lan`, `agents.homelab.lan`, `api.agents.homelab.lan`, `li-swarm.homelab.lan`, `high-fi-demos.homelab.lan`, Supabase (`db.klaut.pro` out of scope).

### Apply Caddy

```bash
rsync -avz -e "ssh -i …/homelab" k8s/edge/Caddyfile scripts/edge-caddy-apply.sh \
  s4il0r@blackpearl:~/staging/homelab-k3s/

ssh -i …/homelab s4il0r@blackpearl
cd ~/staging/homelab-k3s   # or beelink-cleanup mirror
sudo bash scripts/edge-caddy-apply.sh
# First LE cert (needs Fritz :80 → .33):
sudo bash scripts/edge-caddy-apply.sh --certbot-search
```

Do **not** append a bare `search.klaut.pro { reverse_proxy … }` without TLS files — Caddy 2.6 can panic when auto-HTTPS fails (WAN :80 closed).

## LAN edge (li-httpd) — `*.homelab.lan`

| Layer | Component |
|-------|-----------|
| k3s | `--disable traefik` ([docs/k3s-server.md](../../docs/k3s-server.md)) |
| Edge | `li-httpd` + [homelab.httpd.toml](./homelab.httpd.toml) |
| Apply | [scripts/edge-lis-apply.sh](../../scripts/edge-lis-apply.sh) |

Use li-httpd when you want native Li routing on **:80** for LAN hostnames. **Do not** start `li-httpd-homelab-tls` on **:443** while Caddy owns WAN TLS.

Majico staging TOML is merged from `majico.xyz/deploy/staging/edge/majico-staging.httpd.toml`.

## Topology

```
Internet / LAN
      │
      ▼
Fritz WAN :80,:443  ──►  192.168.10.33 (blackpearl)
      │
      ├─ Caddy :443  ──►  search.klaut.pro → :30479
      ├─ Caddy :443  ──►  majico*.d3bu7.com → :30080 / :30000
      └─ Caddy :80   ──►  http://search.klaut.pro (same backend)

LAN only (*.homelab.lan)
      ▼
li-httpd :80  ──►  grafana/signoz/agents/… NodePorts
```

## NodePort reference

| Service | Port |
|---------|------|
| SearXNG | 30479 |
| Supabase Kong | 30480 |
| GitLab | 30481 |
| Dependency-Track | 30482 |
| CWE mirror | 30483 |

## Related

- [docs/search-klaut-pro.md](../../docs/search-klaut-pro.md)
- [docs/fritz-klaut-pro-port-forward.md](../../docs/fritz-klaut-pro-port-forward.md)
- [docs/edge-ingress.md](../../docs/edge-ingress.md)
