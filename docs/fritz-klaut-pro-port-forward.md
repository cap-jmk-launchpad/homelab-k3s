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

## DNS

At your **klaut.pro** DNS provider, each public hostname needs an **A** record to the **same WAN IP** Fritz shows under *Internet* → *Online-Monitor* (e.g. `77.x.x.x`).

| Hostname | Purpose |
|----------|---------|
| `search.klaut.pro` | SearXNG (enabled on edge) |
| `gitlab.klaut.pro` | GitLab (optional — see below) |
| `deps.klaut.pro` | Dependency-Track (optional) |
| `cwe.klaut.pro` | CWE mirror (optional) |

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
