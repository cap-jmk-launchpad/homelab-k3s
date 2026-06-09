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

Requires `~/staging/lic`, `~/staging/li-httpd` (multi-site flatten), and a vhost-capable `li-httpd` binary. Set `LI_HTTPD_ROOT=~/staging/li-httpd` on systemd render-only restarts so flatten uses the synced li-httpd scripts (pool|vhost routes, `upstream_peer=pool|host|port`). After upgrading `lic` or adding many `[[site]]` blocks, rebuild on blackpearl:

**MUST** rebuild blackpearl edge with [scripts/build-edge-li-httpd.sh](../scripts/build-edge-li-httpd.sh) � not plain `lic/scripts/build-li-httpd.sh`. The edge script applies vhost/TLS proxy patches and requires a lic build with a **dynamic** route table (`HTTPD_ROUTES_INIT_CAP` in `li_rt_net.c`, no fixed `HTTPD_MAX_ROUTES`). The homelab flattened config has 200+ routes; default `[limits] max_routes` is **unlimited** (`0` / omitted). Set `max_routes = N` in TOML to pre-allocate and hard-cap; config load fails if flatten emits more than `N` routes. Older lic builds with a fixed route cap silently drop excess routes (404 on `/users/sign_in` while `/health` may still pass).

```bash
bash scripts/build-edge-li-httpd.sh
sudo HOME=/home/s4il0r LIC_ROOT=~/staging/lic LI_HTTPD_ROOT=~/staging/li-httpd \
  bash scripts/edge-lis-apply.sh
```

WAN Let's Encrypt: li-httpd `[server.tls.lets_encrypt]` in the HTTPS overlay ([gen-https-overlay.py](../k8s/edge/gen-https-overlay.py)). Fritz must forward **TCP 80** and **443** → **192.168.10.33** ([fritz-klaut-pro-port-forward.md](fritz-klaut-pro-port-forward.md)).

## Edge reliability (blackpearl)

| Mechanism | Purpose |
|-----------|---------|
| `flock` on `/run/li-httpd/edge-apply.lock` | Serialize config render (HTTP + TLS share runtime files) |
| `.render-ready` marker | TLS unit waits for HTTP render — **never** run `--render-only` from both units |
| `li-httpd-edge-watchdog.timer` | Every 5 min: local `--resolve` probe; heal after 3 local failures (WAN logged only) |
| `edge-health-probe.sh` | ExecStartPost on :80/:443 units (local `--resolve` to 127.0.0.1) |

### Public URL vs LAN hairpin

- **Developers and CI** should use the **public** hostname (e.g. `https://gitlab.lilangverse.xyz`) — that is the supported ingress path through Fritz port-forward to blackpearl.
- **Fritz!Box** must forward **TCP 80** and **443** only to **192.168.10.33** (blackpearl). Any other target on those ports (e.g. nginx on another host) yields small **404** bodies and is not li-httpd.
- From **inside the LAN**, curling the public hostname may hit **NAT hairpin** and fail or reach the wrong server. That is outside li-httpd; do not treat WAN probe failures on blackpearl as edge outages.
- **On blackpearl**, health checks and the edge watchdog use `curl --resolve gitlab.lilangverse.xyz:443:127.0.0.1` so probes always hit local li-httpd. The watchdog restarts edge only after **three consecutive local probe failures**, not WAN failures.
- **LAN users** (`gitlab.lilangverse.xyz`): point the name at **`192.168.10.33`** via Fritz local DNS / DHCP DNS ([homelab-lan-dns.md](homelab-lan-dns.md)) or per-host **`/etc/hosts`** (same line as blackpearl).
- **Workstation HTTPS checks (Windows)**: Schannel certificate revocation and concurrent probes are flaky; **do not** use the desktop as the acceptance gate. On blackpearl, run [scripts/edge-acceptance-gate.sh](../scripts/edge-acceptance-gate.sh) — parallel **18/18**, sequential **18/18**, CSS **10/10** loopback + LAN resolve. **TESTED** or **NOT TESTED** only.

**Never** run debug `li-httpd` from `/tmp` or an interactive shell on blackpearl — orphan processes bind :80/:443 and break production edge + ACME.

After edge changes:

```bash
sudo bash scripts/edge-lis-apply.sh --install-systemd
sudo systemctl restart li-httpd-homelab.service
sleep 2
sudo systemctl restart li-httpd-homelab-tls.service
sudo systemctl enable --now li-httpd-edge-watchdog.timer
```

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
