# Edge ingress (LIS / li-httpd)

Homelab HTTP(S) terminates on **blackpearl** (Linux) with native **li-httpd** from `li/lic` for **WAN** (`*.klaut.pro`) and **LAN** (`*.homelab.lan`). k3s runs with **Traefik disabled**; workloads use **NodePort** (or ClusterIP) and the edge TOML proxies by `Host` to `127.0.0.1:<nodePort>`.

No third-party reverse proxies on the ingress path (no Caddy, in-cluster Ingress, nginx/Traefik/HAProxy/Envoy at edge).

**Policy:** [li-native-edge.md](li-native-edge.md) · enforce with `bash scripts/lint-li-native.sh`

## Topology

```
LAN :80 / :443
        |
        v
  blackpearl â€” li-httpd
        |  LIS-validated TOML -> flatten -> runtime.conf
        |-- majico staging (majico.xyz TOML)
        |-- Grafana, SigNoz, agent-swarm, ... (beelink-cleanup TOML)
        v
  k3s NodePorts on loopback
```

**Config:** [k8s/edge/](../k8s/edge/) â€” [homelab.httpd.toml](../k8s/edge/homelab.httpd.toml), [scripts/edge-lis-apply.sh](../scripts/edge-lis-apply.sh).

## Quick apply (blackpearl)

```bash
cd ~/staging/beelink-cleanup
bash scripts/homelab-edge-policy-check.sh
bash scripts/edge-lis-validate.sh
sudo bash scripts/edge-lis-apply.sh --install-systemd
```

Requires `~/staging/lic` (build via `deploy/staging/scripts/build-li-httpd.sh` or `lic/scripts/build-li-httpd.sh`).

## k3s install

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik ..." sh -
```

See [k3s-server.md](k3s-server.md).

## Validate

```bash
curl -H 'Host: grafana.homelab.lan' http://192.168.10.33/health
curl -H 'Host: staging.majico.xyz' http://192.168.10.33/health
```

Add LAN DNS for `*.homelab.lan` → **`192.168.10.33`** (edge / li-httpd). Full steps: [homelab-lan-dns.md](homelab-lan-dns.md) (Fritz DHCP, optional [k8s/dns/](../k8s/dns/) CoreDNS). SSH to blackpearl uses **`192.168.10.41`**. NodePorts remain for direct debug (either IP on the control-plane node).

## TLS

| Approach | Notes |
|----------|-------|
| LAN HTTP | Current default (`:80`) |
| LAN HTTPS (internal CA) | step-ca ACME → li-httpd manual TLS — [internal-ca-homelab.md](internal-ca-homelab.md) |
| In-cluster TLS | Not used â€” edge TOML routing |

## Firewall

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow OpenSSH
```

Keep k3s API (6443) LAN-only. See [homelab-security-audit.md](homelab-security-audit.md).
## HTTPS (:443)

li-httpd terminates TLS on **:443** using `[server.tls]` in [homelab.httpd.toml](../k8s/edge/homelab.httpd.toml). Default homelab profile uses **self_signed** with `dev = true` (LAN trust / browser warning). Replace with `[server.tls.manual]` for Fritz or internal-CA certs under `/etc/li-httpd/tls/`.

```bash
# On blackpearl after rsync
sudo mkdir -p /var/lib/li-httpd/tls
sudo bash scripts/edge-lis-apply.sh   # runs setup-tls-httpd when needed, then flatten + restart
curl -k -H 'Host: grafana.homelab.lan' https://127.0.0.1/health
```

Fritz!Box: forward **TCP 80** and **TCP 443** → **`192.168.10.33`** (k3s edge node on blackpearl). Plain **:80** remains available when the merged profile includes `:80` sites (separate listener requires a second `li-httpd` instance today). SSH/admin hostname remains **`192.168.10.41`**.

## Related

- [li-native-edge.md](li-native-edge.md) — Li-native edge policy
- [platform-requirements.md](platform-requirements.md) — Linux host requirements
- [homelab-lan-dns.md](homelab-lan-dns.md)
- [k8s/edge/README.md](../k8s/edge/README.md)
