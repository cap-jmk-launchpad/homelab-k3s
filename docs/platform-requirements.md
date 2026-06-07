# Platform requirements (Linux + Li-native edge)

Homelab infrastructure runs on **Linux hosts** with **external Li-native edge ingress** on blackpearl. Cluster workloads expose **NodePort** services; all HTTP(S) routing and TLS terminate on **li-httpd** (LIS stack from `li/lic`).

**Enforcement:** `bash scripts/homelab-edge-policy-check.sh` (also run from `edge-lis-validate.sh`)

## Summary

| Layer | Required platform | Approved software |
|-------|-------------------|-------------------|
| Control plane | Linux (Debian/Ubuntu) | k3s server, `--disable traefik` |
| Standard workers | Linux (Debian/Ubuntu or Pi arm64) | k3s agent |
| Burst GPU worker | WSL2 Ubuntu inside Windows host | k3s agent (Linux VM only) |
| Edge / ingress host | **Linux only** (blackpearl) | **li-httpd** only (`:80` + `:443`) |
| Admin workstation | Windows / macOS / Linux | `kubectl`, SSH — **not** edge |

**Li-native** means WAN (`*.klaut.pro`), LAN (`*.homelab.lan`), and staging hostnames all route through **li-httpd** with LIS-validated TOML. No Caddy, Traefik, nginx, or in-cluster Ingress on the ingress path.

## Edge ingress policy

Config: [k8s/edge/homelab.httpd.toml](../k8s/edge/homelab.httpd.toml). Apply: [scripts/edge-lis-apply.sh](../scripts/edge-lis-apply.sh). Topology: [edge-ingress.md](edge-ingress.md).

New hostnames: NodePort Service → upstream + `[[site]]` in TOML → `edge-lis-validate.sh` → `edge-lis-apply.sh` → update [klaut-pro-products.md](klaut-pro-products.md).

| Allowed | Forbidden on ingress path |
|---------|---------------------------|
| li-httpd + `k8s/edge/homelab.httpd.toml` | Kubernetes `Ingress`, Traefik, Caddy, nginx/HAProxy/Envoy at edge |
| NodePort → `127.0.0.1` on blackpearl | `Service` type `LoadBalancer` |
| TLS via `[server.tls]` in merged TOML | Windows/IIS/WSL as edge host |

### Allowed in-cluster only (not edge ingress)

- **Kong** — Supabase API gateway ([k8s/supabase/](../k8s/supabase/))
- **nginx** — CWE mirror ([k8s/cwe/](../k8s/cwe/))
- **GitLab Omnibus nginx** — inside GitLab pod ([k8s/gitlab/](../k8s/gitlab/))

Legacy Caddy configs: [k8s/edge/deprecated/](../k8s/edge/deprecated/) (reference only).

## Node OS requirements

### Linux-native (required)

| Role | OS | Notes |
|------|-----|-------|
| Control plane | Debian / Ubuntu | [node-prep.md](node-prep.md), [k3s-server.md](k3s-server.md) |
| Edge (blackpearl) | Debian / Ubuntu | li-httpd + systemd + UFW |
| Workers | Debian / Ubuntu or Pi arm64 | [k3s-workers.md](k3s-workers.md) |

Automation assumes: `bash`, `systemctl`, `ufw`, `kubectl`, Linux paths (`/usr/local/bin/li-httpd`, `/var/lib/li-httpd`).

### Windows-adjacent (explicit exceptions)

| Artifact | Role |
|----------|------|
| WSL2 Ubuntu on desktop | Optional k3s **agent** only — [desktop-k3s-worker.md](desktop-k3s-worker.md) |
| `scripts/windows-firewall-*.ps1` | Desktop host firewall (not edge) |
| `scripts/desktop-gpu-tray/` | GPU burst toggle UI |

Windows is **never** an edge, control-plane, or reverse-proxy host.

## k3s install contract

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --disable traefik ..." sh -
```

## Validation

```bash
bash scripts/homelab-edge-policy-check.sh
bash scripts/edge-lis-validate.sh   # LIS oracle + policy lint
```

## Related

- [edge-ingress.md](edge-ingress.md) — operational quick start
- [k8s/edge/README.md](../k8s/edge/README.md) — NodePort matrix
- [homelab-security-audit.md](homelab-security-audit.md) — UFW and exposure
