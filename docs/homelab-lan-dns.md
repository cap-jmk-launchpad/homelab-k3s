# Homelab LAN DNS (`*.homelab.lan`)

Browsers fail on `https://grafana.homelab.lan` (and similar) because **`homelab.lan` is not on public DNS** (by design). Without a LAN resolver or local overrides, the OS has no A record, so the browser never reaches **li-httpd** on **`192.168.10.33`**.

Public DNS (Hostinger, etc.) only serves **`klaut.pro`** → WAN. Internal services use **`*.homelab.lan`** per [k8s/edge/homelab.httpd.toml](../k8s/edge/homelab.httpd.toml).

| Role | IP | Use |
|------|-----|-----|
| k3s edge / li-httpd / LAN DNS | `192.168.10.33` | HTTP(S), `Host:` routing, **DHCP DNS server** |
| SSH / kubectl API | `192.168.10.41` | `ssh s4il0r@blackpearl`, `https://192.168.10.41:6443` |

## Edge hostnames (must resolve to `192.168.10.33`)

| Hostname | Backend (NodePort) |
|----------|-------------------|
| `grafana.homelab.lan` | `:30300` |
| `signoz.homelab.lan` | `:30301` |
| `agents.homelab.lan` | `:30477` |
| `api.agents.homelab.lan` | `:30421` |
| `li-swarm.homelab.lan` | `:30478` |
| `high-fi-demos.homelab.lan` | `:30580` |
| `demo.homelab.lan`, `ducah.homelab.lan` | `:30583` |

Optional (when step-ca / internal CA is deployed): `ca.homelab.lan` → same edge IP.

Public (WAN DNS): `search.klaut.pro` — not part of `homelab.lan`.

## Recommended fix: LAN DNS on k3s (Option B)

Deploy [k8s/dns/](../k8s/dns/) CoreDNS on **blackpearl** (`hostNetwork`, port **53**). Point Fritz!Box DHCP at **`192.168.10.33`** so all LAN clients resolve `*.homelab.lan` automatically.

```bash
# On blackpearl (after rsync repo)
bash scripts/homelab-dns-apply.sh
```

Or from your PC (Git Bash / WSL):

```bash
scp -i homelab -r k8s/dns scripts/homelab-dns-apply.sh s4il0r@blackpearl:~/staging/beelink-cleanup/
ssh -i homelab s4il0r@blackpearl 'bash ~/staging/beelink-cleanup/scripts/homelab-dns-apply.sh'
```

**Note:** If port **53** is already in use (`systemd-resolved` stub), disable the stub on blackpearl or bind DNS to the edge IP only — see [Troubleshooting](#troubleshooting-port-53-in-use).

### Fritz!Box (German UI) — DHCP DNS

Menu names vary slightly by FRITZ!OS; paths are equivalent on current models.

1. **Heimnetz** → **Netzwerk** → **Netzwerkeinstellungen** (or **Heimnetz** → **Heimnetzübersicht** → **Netzwerkeinstellungen**).
2. Under **IPv4-Einstellungen** / **DHCP-Server**:
   - **Lokaler DNS-Server** (or “DNS server in the home network”): enable / set to **`192.168.10.33`**.
   - Leave “DNS server from internet provider” for upstream only if the Fritz UI splits “local” vs “internet”; the homelab CoreDNS forwards other names to `/etc/resolv.conf` (Fritz).
3. **Übernehmen** / apply. Renew DHCP on clients (`ipconfig /renew` on Windows, reconnect Wi‑Fi).
4. **DNS-Rebind-Schutz** (if HTTPS to LAN names fails with “rebind” errors):
   - **Heimnetz** → **Netzwerk** → **Netzwerkeinstellungen** → **DNS-Rebind-Schutz**.
   - Add exception for **`homelab.lan`** (or disable rebind protection for the home network if you accept homelab-only risk).

### Verify

On blackpearl:

```bash
nslookup grafana.homelab.lan 127.0.0.1
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: grafana.homelab.lan' http://192.168.10.33/health
```

On a LAN PC (after DHCP DNS change):

```powershell
nslookup grafana.homelab.lan
# Server should be 192.168.10.33; Address: 192.168.10.33
```

Browser: `http://grafana.homelab.lan/` (or `https://` with `-k` / trusted cert).

## Option A — Fritz local hostname entries (limited)

**Heimnetz** → **Netzwerk** → **Netzwerkeinstellungen** → **DNS-Rebind** / **Lokale DNS-Abfragen** (wording varies):

- Some models: per-device **hostname** in the device list, not a full zone file.
- You must add **each** FQDN (`grafana.homelab.lan`, `signoz.homelab.lan`, …) — tedious and capped (~20 entries on many Fritz boxes).
- Wildcard `*.homelab.lan` is **not** supported.

Use only for a couple of hosts; prefer Option B for the full edge list.

## Option C — Windows hosts file (quick fix)

Edit as Administrator: `C:\Windows\System32\drivers\etc\hosts`

```
192.168.10.33 grafana.homelab.lan
192.168.10.33 signoz.homelab.lan
192.168.10.33 agents.homelab.lan
192.168.10.33 api.agents.homelab.lan
192.168.10.33 li-swarm.homelab.lan
192.168.10.33 high-fi-demos.homelab.lan
192.168.10.33 demo.homelab.lan
192.168.10.33 ducah.homelab.lan
```

No Fritz change; only fixes **this PC**. Browsers on phones/Mac still need Option A or B.

## Comparison

| Option | Pros | Cons |
|--------|------|------|
| A Fritz per-host | No k8s deploy | No wildcard; many manual entries |
| B k3s CoreDNS + Fritz DHCP | All LAN clients; wildcard `*.homelab.lan` | Port 53 on blackpearl; one-time Fritz DHCP |
| C Windows hosts | Immediate on one PC | Per-machine; easy to forget |

## Troubleshooting: port 53 in use

On blackpearl:

```bash
sudo ss -ulnp | grep ':53 '
```

If `systemd-resolved` holds `127.0.0.53:53`, either:

- Disable stub: edit `/etc/systemd/resolved.conf` → `DNSStubListener=no`, `sudo systemctl restart systemd-resolved`, or
- Stop resolved and use static `resolv.conf` pointing at Fritz (`192.168.10.254` / `fritz.box`).

Then restart DNS: `kubectl -n homelab-dns rollout restart daemonset/homelab-lan-coredns`.

## Related

- [docs/edge-ingress.md](edge-ingress.md) — li-httpd topology
- [k8s/edge/README.md](../k8s/edge/README.md) — NodePort map
- [k8s/dns/README.md](../k8s/dns/README.md) — manifest details
- Internal CA: when `docs/internal-ca-homelab.md` exists in homelab-k3s, add `ca.homelab.lan` to [k8s/dns/coredns-configmap.yaml](../k8s/dns/coredns-configmap.yaml)
