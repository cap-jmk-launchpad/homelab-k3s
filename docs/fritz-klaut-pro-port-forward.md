# Fritz!Box — expose klaut.pro to homelab edge

Public DNS **A** records for `*.klaut.pro` point at your Fritz!Box **WAN IP**. The router must forward HTTP(S) to the k3s edge host, not the SSH/admin DHCP address.

## Target host

| Role | IP | Use |
|------|-----|-----|
| k3s edge (Caddy / NodePort) | **192.168.10.33** | Fritz **Portfreigabe** destination |
| SSH / admin hostname | 192.168.10.41 | `ssh s4il0r@blackpearl` only |

Same physical machine (blackpearl); two addresses on `enp1s0`.

## Fritz!Box UI (manual — no API in this repo)

1. Open **http://fritz.box** → **Internet** → **Freigaben** → **Portfreigaben** (or **MyFRITZ!** → Gerät freigeben).
2. Add device **blackpearl** / the host that owns **192.168.10.33** (or enter IP manually).
3. Create **two** rules (TCP only):

| Name | Protokoll | Port extern | Port intern | Ziel-IP |
|------|-----------|-------------|-------------|---------|
| homelab-http | TCP | **80** → **80** | **80** | **192.168.10.33** |
| homelab-https | TCP | **443** → **443** | **443** | **192.168.10.33** |

4. Save. Wait ~30s, then verify from outside the LAN:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://search.klaut.pro/healthz
curl -sS -o /dev/null -w '%{http_code}\n' https://search.klaut.pro/healthz
```

Both should return **200** when SearXNG is running and [edge-caddy-apply.sh](../scripts/edge-caddy-apply.sh) has installed the LE cert.

## Deployed services (k3s, 2026-06)

All backends listen on **NodePorts** on blackpearl loopback; Caddy on **:80** / **:443** proxies WAN hostnames to `127.0.0.1:<port>`. Full matrix: [klaut-pro-products.md](klaut-pro-products.md#homelab-inventory-current).

| Service | Namespace | NodePort | WAN hostname | Status |
|---------|-----------|----------|--------------|--------|
| SearXNG | `searxng` | 30479 | `search.klaut.pro` | **Live** HTTPS |
| Supabase | `supabase` | 30480 | — | Running (LAN / in-cluster only) |
| GitLab | `gitlab` | 30481 | `gitlab.klaut.pro` | Running; WAN route optional |
| Dependency-Track | `dependency-track` | 30482 | `deps.klaut.pro` | Running; WAN route optional |
| CWE mirror | `cwe` | 30483 | `cwe.klaut.pro` | Running; WAN route optional |

Enable optional WAN: uncomment blocks in [k8s/edge/Caddyfile](../k8s/edge/Caddyfile) + upstreams in [homelab.httpd.toml](../k8s/edge/homelab.httpd.toml), then `sudo bash scripts/edge-caddy-apply.sh`.

## DNS

At your **klaut.pro** DNS provider, each public hostname needs an **A** record to the **same WAN IP** Fritz shows under *Internet* → *Online-Monitor* (e.g. `77.x.x.x`).

| Hostname | Purpose | Edge today |
|----------|---------|------------|
| `search.klaut.pro` | SearXNG | **Enabled** (HTTP + HTTPS) |
| `gitlab.klaut.pro` | GitLab CE | Optional — uncomment Caddy + DNS |
| `deps.klaut.pro` | Dependency-Track | Optional |
| `cwe.klaut.pro` | CWE mirror | Optional |

Optional LAN testing before WAN DNS: Fritz **DNS-Rebind** / local DNS or `/etc/hosts` → `192.168.10.33`.

## What runs on blackpearl

- **Caddy** listens on **:80** and **:443** (WAN edge today).
- **li-httpd** homelab units are for `*.homelab.lan` on :80 when enabled; do **not** bind :443 while Caddy is the TLS terminator (port conflict).

Apply Caddy routes: `sudo bash scripts/edge-caddy-apply.sh`  
Obtain / refresh search cert: `sudo bash scripts/edge-caddy-apply.sh --certbot-search` (needs TCP 80 forward first).

## Troubleshooting

| Symptom | Likely cause |
|---------|----------------|
| HTTP 200, HTTPS TLS alert | LE cert missing; run `--certbot-search` after :80 forward works |
| Connection refused on WAN | Fritz rule points at **.41** instead of **.33**, or rule disabled |
| Caddy panic on reload | Avoid bare `search.klaut.pro { reverse_proxy ... }` without manual TLS when :80 was closed; use repo `Caddyfile` + apply script |
| ACME fails | WAN :80 not reaching 192.168.10.33 |
