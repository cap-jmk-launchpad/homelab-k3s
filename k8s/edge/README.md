# Homelab edge ingress (blackpearl)

Traffic flow for **WAN** (`*.klaut.pro`, `majico.d3bu7.com`) and **LAN** (`*.homelab.lan`).

## WAN edge (Caddy) — default for klaut.pro

| Port | Process | Scope |
|------|---------|--------|
| **80** | Caddy | HTTP + ACME; `http://search.klaut.pro` |
| **443** | Caddy | TLS (Majico manual certs + klaut LE certs) |

**Fritz!Box:** TCP **80** and **443** → **192.168.10.33** — see [docs/fritz-klaut-pro-port-forward.md](../../docs/fritz-klaut-pro-port-forward.md).

| Hostname | Namespace | Backend | WAN status |
|----------|-----------|---------|------------|
| `search.klaut.pro` | `searxng` | `127.0.0.1:30479` | **Live** — HTTPS on WAN |
| `gitlab.klaut.pro` | `gitlab` | `127.0.0.1:30481` | **WAN** — GitLab on `engine` NodePort |
| `deps.klaut.pro` | `dependency-track` | `127.0.0.1:30482` | **WAN** |
| `cwe.klaut.pro` | `cwe` | `127.0.0.1:30483` | **WAN** — `/health`, `/manifest.json` |
| `vault.klaut.pro` | *(HCP pending)* | — | **503 placeholder** until `VAULT_*` bootstrap |
| `majico.d3bu7.com`, `api.majico.d3bu7.com`, `supabase.majico.d3bu7.com` | Majico NodePorts | Enabled (manual TLS under `/etc/caddy/certs/`) |

**Internal-only** (no `*.klaut.pro` route): `grafana.homelab.lan`, `signoz.homelab.lan`, `agents.homelab.lan`, `api.agents.homelab.lan`, `li-swarm.homelab.lan`, `high-fi-demos.homelab.lan`, Supabase (`db.klaut.pro` out of scope).

### Apply Caddy

```bash
rsync -avz -e "ssh -i …/homelab" k8s/edge/Caddyfile scripts/edge-caddy-apply.sh \
  s4il0r@blackpearl:~/staging/homelab-k3s/

ssh -i …/homelab s4il0r@blackpearl
cd ~/staging/homelab-k3s   # or beelink-cleanup mirror
sudo bash scripts/edge-caddy-apply.sh
# LE certs for klaut hostnames (needs Fritz :80 → .33):
sudo bash scripts/edge-caddy-apply.sh --certbot-klaut
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

Canonical inventory: [docs/klaut-pro-products.md](../../docs/klaut-pro-products.md#homelab-inventory-current).

| Service | Namespace | NodePort | WAN |
|---------|-----------|----------|-----|
| SearXNG | `searxng` | 30479 | `search.klaut.pro` (live) |
| Supabase Kong | `supabase` | 30480 | internal only |
| GitLab | `gitlab` | 30481 | `gitlab.klaut.pro` optional |
| Dependency-Track | `dependency-track` | 30482 | `deps.klaut.pro` optional |
| CWE mirror | `cwe` | 30483 | `cwe.klaut.pro` optional |

## Related

- [docs/search-klaut-pro.md](../../docs/search-klaut-pro.md)
- [docs/fritz-klaut-pro-port-forward.md](../../docs/fritz-klaut-pro-port-forward.md)
- [docs/edge-ingress.md](../../docs/edge-ingress.md)
