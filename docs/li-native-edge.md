# Li-native edge policy

All homelab HTTP(S) ingress — WAN (`*.klaut.pro`), LAN (`*.homelab.lan`), and staging hostnames — terminates on **blackpearl** (Linux) with native **li-httpd** from `li/lic` (LIS). No third-party reverse proxies sit on the ingress path.

Linux host requirements: [platform-requirements.md](platform-requirements.md)

## What “li-native” means

| Layer | Required | Forbidden on ingress path |
|-------|----------|---------------------------|
| k3s | `--disable traefik` at install | Traefik, nginx Ingress Controller, HAProxy Ingress |
| In-cluster | `Service` type **NodePort** or **ClusterIP** | `kind: Ingress`, `ingress.enabled: true` in Helm |
| Edge (blackpearl) | **li-httpd** + LIS-validated TOML → `127.0.0.1:<nodePort>` | Caddy, nginx, Apache httpd, HAProxy as WAN/LAN front door |
| TLS | `[server.tls]` in merged TOML (`lets_encrypt`, `manual`, or `self_signed`) | Separate cert daemons that own `:443` beside li-httpd |

Workloads never terminate TLS in-cluster for homelab edge traffic; the edge TOML routes by `Host` to loopback NodePorts.

## Topology

```
Internet / LAN
      │
      ▼
Fritz :80,:443 → 192.168.10.33 (blackpearl)
      │
      ▼
li-httpd :80  (HTTP + ACME HTTP-01)
li-httpd :443 (TLS overlay from gen-https-overlay.py)
      │
      ├── *.klaut.pro     → NodePorts (search, gitlab, deps, cwe, vault, …)
      ├── *.homelab.lan   → NodePorts (grafana, signoz, agents, …)
      └── majico staging  → merged from majico-staging.httpd.toml
```

## Source of truth

| Artifact | Role |
|----------|------|
| [k8s/edge/homelab.httpd.toml](../k8s/edge/homelab.httpd.toml) | Homelab + klaut WAN/LAN routes |
| `majico.xyz/.../majico-staging.httpd.toml` | Majico staging (merged on apply) |
| [scripts/edge-lis-apply.sh](../scripts/edge-lis-apply.sh) | Flatten, TLS setup, systemd reload |
| [scripts/edge-lis-validate.sh](../scripts/edge-lis-validate.sh) | LIS oracle + li-native lint |

Legacy Caddy configs live under [k8s/edge/deprecated/](../k8s/edge/deprecated/) for reference only.

## Apply (blackpearl)

```bash
cd ~/staging/beelink-cleanup
bash scripts/edge-lis-validate.sh
sudo bash scripts/edge-lis-apply.sh --install-systemd
```

Requires `~/staging/lic` (build via `lic/scripts/build-li-httpd.sh`) and `~/staging/li-httpd` (multi-site flatten scripts for merged edge TOML).

WAN Let's Encrypt: li-httpd `[server.tls.lets_encrypt]` in the HTTPS overlay ([gen-https-overlay.py](../k8s/edge/gen-https-overlay.py)). Fritz must forward **TCP 80** and **443** → **192.168.10.33** ([fritz-klaut-pro-port-forward.md](fritz-klaut-pro-port-forward.md)).

## Validate

```bash
# Lint (local or CI)
bash scripts/lint-li-native.sh

# LAN
curl -H 'Host: grafana.homelab.lan' http://127.0.0.1/health

# WAN (after DNS + port-forward)
curl -sS -o /dev/null -w '%{http_code}\n' https://search.klaut.pro/health
```

## Adding a new public hostname

1. Expose the workload with a **NodePort** `Service` (no Ingress).
2. Add `[upstreams.<id>]` and `[[site]]` to `homelab.httpd.toml` (or the majico TOML if staging-only).
3. Add the hostname to `HOMELAB_ACME_DOMAINS` if WAN HTTPS is needed.
4. Run `edge-lis-validate.sh` then `edge-lis-apply.sh`.
5. Update [klaut-pro-products.md](klaut-pro-products.md) inventory.

## Enforcement

[scripts/lint-li-native.sh](../scripts/lint-li-native.sh) fails on:

- `kind: Ingress` in `k8s/`
- `ingress.enabled: true` in Helm values
- Active `reverse_proxy` / Caddy blocks outside `k8s/edge/deprecated/`
- Scripts that invoke `edge-caddy-apply.sh` (except the deprecated wrapper itself)
- Missing required WAN hostnames in `homelab.httpd.toml`

[scripts/homelab-edge-policy-check.sh](../scripts/homelab-edge-policy-check.sh) runs `lint-li-native.sh` plus Linux-native manifest checks.

Run before every edge change:

```bash
bash scripts/lint-li-native.sh
```

## Related

- [platform-requirements.md](platform-requirements.md) — Linux host requirements
- [edge-ingress.md](edge-ingress.md) — operational quick start
- [k8s/edge/README.md](../k8s/edge/README.md) — NodePort inventory
- [k3s-server.md](k3s-server.md) — Traefik disabled at install
- [AGENTS.md](../AGENTS.md) — contributor / agent guide
