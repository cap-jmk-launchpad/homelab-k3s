# Homelab edge ingress (blackpearl) — li-native

All HTTP(S) ingress uses **li-httpd** (LIS). No Caddy, Traefik, or in-cluster Ingress on the path. Policy: [docs/platform-requirements.md](../../docs/platform-requirements.md).

Traffic flow for **WAN** (`*.klaut.pro`, `majico.d3bu7.com`) and **LAN** (`*.homelab.lan`).

## Edge (li-httpd)

| Port | Process | Scope |
|------|---------|--------|
| **80** | li-httpd | HTTP + ACME HTTP-01; all hostnames |
| **443** | li-httpd (TLS overlay) | WAN LE + LAN/internal TLS |

**Fritz!Box:** TCP **80** and **443** → **192.168.10.33** — see [docs/fritz-klaut-pro-port-forward.md](../../docs/fritz-klaut-pro-port-forward.md).

| Hostname | Namespace | Backend | WAN status |
|----------|-----------|---------|------------|
| `search.klaut.pro` | `searxng` | `127.0.0.1:30479` | **Live** |
| `gitlab.klaut.pro` | `gitlab` | `127.0.0.1:30481` | **WAN** |
| `deps.klaut.pro` | `dependency-track` | `127.0.0.1:30482` | **WAN** |
| `cwe.klaut.pro` | `cwe` | `127.0.0.1:30483` | **WAN** |
| `vault.klaut.pro` | `vault` | static + `127.0.0.1:30485` | **WAN** |
| `majico.d3bu7.com`, `api.majico.d3bu7.com`, `supabase.majico.d3bu7.com` | Majico NodePorts | merged TOML | staging |
| `chat.homelab.lan`, `chat.obsevia.d3bu7.com` | chat staging | `127.0.0.1:30581` | LAN / staging |
| `dp.homelab.lan`, `dp.obsevia.com` | DP demo | `127.0.0.1:30582` | LAN / demo |

**Internal-only** (no `*.klaut.pro` route): `grafana.homelab.lan`, `signoz.homelab.lan`, `agents.homelab.lan`, `api.agents.homelab.lan`, `li-swarm.homelab.lan`, `high-fi-demos.homelab.lan`, Supabase (`db.klaut.pro` out of scope).

### Apply

```bash
rsync -avz -e "ssh -i …/homelab" k8s/edge/ scripts/edge-lis-*.sh scripts/lint-li-native.sh \
  s4il0r@blackpearl:~/staging/homelab-k3s/

ssh -i …/homelab s4il0r@blackpearl
cd ~/staging/homelab-k3s
bash scripts/edge-lis-validate.sh
sudo bash scripts/edge-lis-apply.sh --install-systemd
```

Legacy Caddy config: [deprecated/Caddyfile.legacy](./deprecated/Caddyfile.legacy) (do not apply).

## k3s

| Layer | Component |
|-------|-----------|
| k3s | `--disable traefik` ([docs/k3s-server.md](../../docs/k3s-server.md)) |
| Edge | `li-httpd` + [homelab.httpd.toml](./homelab.httpd.toml) |
| Majico | merged from `majico.xyz/deploy/staging/edge/majico-staging.httpd.toml` |
| Validate | [scripts/edge-lis-validate.sh](../../scripts/edge-lis-validate.sh) (LIS + lint-li-native) |

## Topology

```
Internet / LAN
      │
      ▼
Fritz WAN :80,:443  ──►  192.168.10.33 (blackpearl)
      │
      ▼
li-httpd :80 / :443
      ├── search.klaut.pro → :30479
      ├── gitlab/deps/cwe/vault.klaut.pro → NodePorts
      ├── majico*.d3bu7.com → majico NodePorts (merged TOML)
      └── *.homelab.lan → grafana/signoz/agents/… NodePorts
```

## NodePort reference

Canonical inventory: [docs/klaut-pro-products.md](../../docs/klaut-pro-products.md#homelab-inventory-current).

| Service | Namespace | NodePort | WAN |
|---------|-----------|----------|-----|
| SearXNG | `searxng` | 30479 | `search.klaut.pro` |
| Supabase Kong | `supabase` | 30480 | internal only |
| GitLab | `gitlab` | 30481 | `gitlab.klaut.pro` |
| Dependency-Track | `dependency-track` | 30482 | `deps.klaut.pro` |
| CWE mirror | `cwe` | 30483 | `cwe.klaut.pro` |

## Internal TLS (`*.homelab.lan`)

WAN **Let's Encrypt** is issued via li-httpd `[server.tls.lets_encrypt]` in the HTTPS overlay. LAN hostnames can use **step-ca** (namespace `step-ca`, NodePort **30484**) — [docs/internal-ca-homelab.md](../../docs/internal-ca-homelab.md).

## DNS (LAN)

Point edge traffic at **`192.168.10.33`** (li-httpd on blackpearl). **Recommended:** [k8s/dns/](../dns/) CoreDNS + Fritz DHCP DNS → `192.168.10.33` — [docs/homelab-lan-dns.md](../../docs/homelab-lan-dns.md). SSH/admin: **`192.168.10.41`**.

| Host |
|------|
| `grafana.homelab.lan`, `signoz.homelab.lan`, `agents.homelab.lan` |
| `api.agents.homelab.lan`, `li-swarm.homelab.lan`, `high-fi-demos.homelab.lan` |

## Validate

```bash
bash scripts/lint-li-native.sh
curl -H 'Host: grafana.homelab.lan' http://127.0.0.1/health
curl -sS -o /dev/null -w '%{http_code}\n' https://search.klaut.pro/health
```

## Related

- [docs/platform-requirements.md](../../docs/platform-requirements.md)
- [docs/homelab-lan-dns.md](../../docs/homelab-lan-dns.md)
- [docs/internal-ca-homelab.md](../../docs/internal-ca-homelab.md)
- [docs/search-klaut-pro.md](../../docs/search-klaut-pro.md)
- [docs/fritz-klaut-pro-port-forward.md](../../docs/fritz-klaut-pro-port-forward.md)
- [docs/edge-ingress.md](../../docs/edge-ingress.md)
