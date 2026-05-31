# Edge ingress (LIS / li-httpd)

Homelab HTTP(S) terminates on **blackpearl** with native **li-httpd** from `li/lic`. k3s runs with **Traefik disabled**; workloads use **NodePort** (or ClusterIP) and the edge TOML proxies by `Host` to `127.0.0.1:<nodePort>`.

No third-party reverse proxies on the ingress path.

## Topology

```
LAN :80 / :443
        |
        v
  blackpearl — li-httpd
        |  LIS-validated TOML -> flatten -> runtime.conf
        |-- majico staging (majico.xyz TOML)
        |-- Grafana, SigNoz, agent-swarm, ... (beelink-cleanup TOML)
        v
  k3s NodePorts on loopback
```

**Config:** [k8s/edge/](../k8s/edge/) — [homelab.httpd.toml](../k8s/edge/homelab.httpd.toml), [scripts/edge-lis-apply.sh](../scripts/edge-lis-apply.sh).

## Quick apply (blackpearl)

```bash
cd ~/staging/beelink-cleanup
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
curl -H 'Host: grafana.homelab.lan' http://192.168.10.41/health
curl -H 'Host: staging.majico.xyz' http://192.168.10.41/health
```

Add LAN DNS for `*.homelab.lan` -> `192.168.10.41`. NodePorts remain for direct debug.

## TLS

| Approach | Notes |
|----------|-------|
| LAN HTTP | Current default (`:80`) |
| Edge TLS | Fritz!box, manual certs, or future `li-httpd setup-tls` in lic |
| In-cluster TLS | Not used — edge TOML routing |

## Firewall

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow OpenSSH
```

Keep k3s API (6443) LAN-only. See [homelab-security-audit.md](homelab-security-audit.md).