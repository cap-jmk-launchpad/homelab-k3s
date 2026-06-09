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

## WAN GitLab on LAN (`gitlab.lilangverse.xyz`)

Fritz!Box forwards **TCP 443** (and **80**) to **192.168.10.33** only. From a machine on the same LAN (including blackpearl):

| Probe | Typical result | Why |
|-------|----------------|-----|
| `curl https://gitlab.lilangverse.xyz/...` (system resolver → public WAN IP) | **Connection refused / timeout** | Hairpin NAT often disabled; traffic leaves LAN and cannot re-enter on `.33`. |
| `curl --resolve gitlab.lilangverse.xyz:443:77.x.x.x ...` (public IP) | **200** on small paths | Hairpin or off-LAN path works when the forward target is reachable. |
| `curl --resolve gitlab.lilangverse.xyz:443:127.0.0.1 ...` | **200** for `/users/sign_in` | Hits local li-httpd; use for edge health on blackpearl. |

**Split-DNS fix (recommended on LAN):** resolve `gitlab.lilangverse.xyz` (and `registry.gitlab.lilangverse.xyz` if used) to **`192.168.10.33`** via CoreDNS zone override ([k8s/dns/](../k8s/dns/)) or per-host `/etc/hosts`:

```
192.168.10.33 gitlab.lilangverse.xyz registry.gitlab.lilangverse.xyz
```

The edge watchdog treats **WAN** probe failures as **informational only** (local `127.0.0.1` resolve is authoritative) so hairpin/DNS gaps do not restart li-httpd.

**LAN clients:** add the hosts block above *or* configure Fritz **local DNS** / DHCP DNS server **`192.168.10.33`** (CoreDNS zone) so `gitlab.lilangverse.xyz` resolves to the edge IP without hairpin.

**Windows workstation manual probes:** use `curl.exe --ssl-no-revoke` and either the hosts/DNS split above or:

```powershell
curl.exe --ssl-no-revoke --resolve gitlab.lilangverse.xyz:443:192.168.10.33 https://gitlab.lilangverse.xyz/users/sign_in
```

### Windows Schannel + large asset downloads (2026-06-09)

Path isolation on blackpearl shows the edge is healthy; workstation `curl.exe` (Schannel) is not a reliable acceptance probe for large static assets.

| Probe path | Typical pass rate | Notes |
|------------|-------------------|-------|
| blackpearl `--resolve …:127.0.0.1` | **10/10** | loopback li-httpd |
| blackpearl `--resolve …:192.168.10.33` | **10/10** | same TLS path as LAN clients |
| Windows `--resolve …:192.168.10.33` | **~2–4/10** | HTTP **200**, `Content-Length: 835437`, but `size_download` truncated |

Truncation is **client-side Schannel read behavior** (not li-httpd route loss): headers are complete while the TLS body stream stops early. `--http1.1`, `--no-sessionid`, `--no-keepalive`, and longer spacing do not fix it reliably.

**Workarounds for LAN developers:**

1. **Browsers** with split-DNS (`192.168.10.33 gitlab.lilangverse.xyz` in hosts or CoreDNS DHCP) — normal GitLab UI use.
2. **Acceptance / watchdog gate** — run [scripts/edge-css-probe.sh](../scripts/edge-css-probe.sh) on blackpearl only (10/10 loopback + 10/10 LAN resolve).
3. **Windows reporting** — [scripts/edge-css-probe.ps1](../scripts/edge-css-probe.ps1) documents pass rate; do not block edge deploy on workstation curl alone.

Do **not** treat intermittent workstation WAN curls as edge failures; blackpearl acceptance uses **10/10** local `--resolve` to `127.0.0.1` and **10/10** `--resolve` to `192.168.10.33` before re-enabling `li-httpd-edge-watchdog.timer`.
