# Homelab LAN DNS (`*.homelab.lan`)

CoreDNS **DaemonSet** on **blackpearl** (`hostNetwork`, port **53**) answers `*.homelab.lan` with **`192.168.10.33`** (li-httpd edge) and forwards other queries to the node’s upstream (`/etc/resolv.conf`, usually Fritz!Box).

| Doc | Purpose |
|-----|---------|
| [docs/homelab-lan-dns.md](../../docs/homelab-lan-dns.md) | Why browsers fail today, Fritz!Box DHCP/DNS, Windows hosts quick fix |

## Apply (blackpearl)

```bash
cd ~/staging/beelink-cleanup   # or homelab-k3s checkout
kubectl apply -k k8s/dns/
# Or: bash scripts/homelab-dns-apply.sh
```

Allow LAN DNS on UFW (once):

```bash
sudo ufw allow from 192.168.10.0/24 to any port 53 proto udp comment homelab-lan-dns
sudo ufw allow from 192.168.10.0/24 to any port 53 proto tcp comment homelab-lan-dns
```

If **systemd-resolved** binds stub port 53 on the node, stop/disable stub listener or move it before the DaemonSet can bind (see homelab-lan-dns.md).

## Verify

```bash
nslookup grafana.homelab.lan 127.0.0.1
nslookup grafana.homelab.lan 192.168.10.33
```

From a LAN client after Fritz DHCP DNS = `192.168.10.33`:

```bash
nslookup grafana.homelab.lan
curl -sS -o /dev/null -w '%{http_code}\n' http://grafana.homelab.lan/health
```

## Hostnames (edge)

From [homelab.httpd.toml](../edge/homelab.httpd.toml): `grafana`, `signoz`, `agents`, `api.agents`, `li-swarm`, `ducah` under `.homelab.lan`. Wildcard template covers future edge hosts.
