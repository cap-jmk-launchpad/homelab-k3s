# Portfolio edge incident — 2026-08-26

## Symptom

`https://www.julianmkleber.com` (and `julianmkleber.com`) served a certificate for `lip.lilangverse.xyz` and proxied to the **lip registry** (`k8s NodePort 30422`) instead of the **portfolio** backend (`NodePort 30585`). Browser error:

> This server could not prove that it is `www.julianmkleber.com`; its security certificate is from `lip.lilangverse.xyz`.

HTTP `Host: www.julianmkleber.com` also returned lip content or 502, not portfolio.

## Root causes (all 5 must align)

| Layer | Before | Why it caused fallback to lip |
|-------|--------|------------------------------|
| **`k8s/edge/homelab.httpd.toml` [[site]]** | Only `portfolio.homelab.lan` existed; no `host = "julianmkleber.com"` / `www` | li-httpd had no SNI match → nginx default vhost cert (lip or agentic-book) served |
| **`[upstreams.portfolio]` peers** | `["http://192.168.10.26:30585"]` (deck LAN IP only) | Loopback `127.0.0.1:30585` health probe on blackpearl failed → upstream marked down; fallback not configured. Deck IP is DHCP/fragile. |
| **`k8s/edge/gen-https-overlay.py` `WAN_TLS_SUFFIXES`** | `(".klaut.pro", ".d3bu7.com", ".lilangverse.xyz", ".obsevia.com", ".librebase.xyz")` | `julianmkleber.com` not recognised as WAN → `_wan_site_hosts()` filtered it out → TLS overlay never included it |
| **`WAN_TLS_SUFFIXES` apex logic** | `host.endswith(suffix)` only | `julianmkleber.com` (apex, no dot) failed `endswith(".julianmkleber.com")` → only `www` would have been recognised |
| **`gen-https-overlay.py` `ACME_DOMAINS`** | Missing `julianmkleber.com,www.julianmkleber.com` | LE cert `homelab-edge` / `majico.d3bu7.com` SAN never covered portfolio host → `_tls_block()` fell back to partial `majico` or `gitlab` cert, not portfolio |
| **`k8s/edge/nginx-julianmkleber.conf`** | Did not exist | `nginx :443` (public Fritz → blackpearl) had no `server_name julianmkleber.com` → default server cert (lip) served for unknown SNI |
| **`scripts/homelab-edge-policy-check.sh`** | Required hosts only `search/gitlab/deps/cwe/vault.klaut.pro`; blocked `nginx-*.conf` as “non-approved” | CI lint passed while portfolio was broken; no healer to auto-patch |

## Fix (committed)

* **`homelab.httpd.toml:97`** → `peers = ["http://127.0.0.1:30585", "http://192.168.10.26:30585"]` (loopback primary + deck fallback, li-httpd health skips failing peer)
* **`homelab.httpd.toml:364-382`** → added `[[site]] julianmkleber.com` + `www.julianmkleber.com` → `proxy:portfolio`
* **`gen-https-overlay.py:32`** → added `".julianmkleber.com"`; `py:35` apex-aware `host == suffix.lstrip(".") or host.endswith(suffix)`
* **`gen-https-overlay.py:68`** → `ACME_DOMAINS` includes `julianmkleber.com,www.julianmkleber.com`
* **`k8s/edge/nginx-julianmkleber.conf`** (new) + **`scripts/edge-nginx-apply.sh:111`** conditional include when LE cert exists
* **`scripts/edge-julianmkleber-certbot.sh`** (new) — `certbot --webroot -w /var/lib/li-httpd -d julianmkleber.com -d www.julianmkleber.com`
* **`scripts/homelab-edge-policy-check.sh`** → now heals:
  - missing portfolio `[[site]]`
  - upstream without loopback / misroute `proxy:lip`
  - missing `WAN_TLS_SUFFIXES`/apex handling
  - missing `ACME_DOMAINS`
  - missing `nginx-julianmkleber.conf`
  - whitelist `*.httpd.toml` + `nginx-*.conf` (was false-positive)
  - supports `--fix` to patch repo in-place (idempotent)

## Healer usage

The canonical healer is now **`homelab-edge-policy-check.sh`** (used by `lint-li-native.sh`). The old `edge-config-healer.sh` is a deprecated wrapper that forwards to it plus live SNI checks on blackpearl.

```bash
# CI / local dry-run (fails if broken)
bash scripts/homelab-edge-policy-check.sh
bash scripts/lint-li-native.sh          # alias

# auto-fix portfolio-style SNI/misroute (patches TOML + overlay + nginx skeleton)
bash scripts/homelab-edge-policy-check.sh --fix
git diff  # review

# validate + render
bash scripts/edge-lis-validate.sh
python3 k8s/edge/gen-https-overlay.py k8s/edge/homelab.httpd.toml -o /tmp/out.toml && grep julianmkleber /tmp/out.toml

# on blackpearl: issue LE cert + reload
sudo bash scripts/edge-julianmkleber-certbot.sh
# or generic:
sudo certbot certonly --webroot -w /var/lib/li-httpd -d julianmkleber.com -d www.julianmkleber.com
sudo bash scripts/edge-nginx-apply.sh
sudo bash scripts/edge-lis-apply.sh
curl -k --resolve www.julianmkleber.com:443:127.0.0.1 https://www.julianmkleber.com/health
openssl s_client -connect 127.0.0.1:443 -servername www.julianmkleber.com </dev/null 2>/dev/null | openssl x509 -noout -ext subjectAltName | grep julianmkleber
```

Live healer on blackpearl (needs `/etc/letsencrypt`):

```bash
bash scripts/edge-config-healer.sh --check   # live SAN + Host-header probe
bash scripts/edge-config-healer.sh --fix     # forwards to policy checker
```

Watchdogs remain for runtime health: `gitlab-edge-watchdog.sh` (engine DHCP upstream + pod) + `edge-watchdog.sh` (nginx + li-httpd probe via `gitlab.lilangverse.xyz`) are both folded into the **unified `cluster-watchdog` timer** on blackpearl ([docs/cluster-watchdog.md](cluster-watchdog.md)). Portfolio runtime health is now actively kept up by `cluster-watchdog`'s `keep_portfolio_up` phase (probes `127.0.0.1:30585` + WAN `https://www.julianmkleber.com/health`, restarts the backend pod behind NodePort 30585 if down, and re-applies the edge config + LE cert if the WAN check fails).

## How to add the next WAN host without repeating this

1. NodePort `Service` (no `Ingress`)
2. `[upstreams.<id>]` + `[[site]]` in `homelab.httpd.toml`
3. `WAN_TLS_SUFFIXES` + `ACME_DOMAINS` in `gen-https-overlay.py` (or expect `homelab-edge-policy-check.sh --fix` to patch it)
4. `k8s/edge/nginx-<host>.conf` + wire in `edge-nginx-apply.sh` (or let healer scaffold)
5. `bash scripts/homelab-edge-policy-check.sh --fix && bash scripts/lint-li-native.sh`
6. DNS `A @/www → Fritz WAN` then `edge-julianmkleber-certbot.sh` pattern

## References

* `docs/li-native-edge.md` — Li-native edge policy
* `docs/edge-ingress.md` — quick apply
* `scripts/homelab-edge-policy-check.sh` — policy + healer (`--fix`)
* `scripts/edge-config-healer.sh` — deprecated wrapper (live SAN probe)
* `k8s/edge/README.md` — NodePort inventory
