# Public access — no VPN required

Developers worldwide use **`https://gitlab.lilangverse.xyz`** directly. The homelab edge is **li-httpd** on blackpearl (`192.168.10.33`); GitLab Omnibus stays on k3s NodePort **30481** — no second install, no VPN, no NodePort in normal workflows.

## Path

```
Internet / developers
        │
        ▼
Fritz!Box WAN (77.23.124.82)  TCP 80 + 443  →  192.168.10.33 (blackpearl)
        │
        ▼
li-httpd :80 (HTTP + ACME)  /  :443 (TLS)
        │  Host: gitlab.lilangverse.xyz
        ▼
127.0.0.1:30481  (gitlab Service NodePort → Omnibus on engine)
```

Registry (when enabled): `registry.gitlab.lilangverse.xyz` → same upstream.

## Edge routes (source of truth)

In [k8s/edge/homelab.httpd.toml](../k8s/edge/homelab.httpd.toml):

| Hostname | Upstream | Notes |
|----------|----------|-------|
| `gitlab.lilangverse.xyz` | `proxy:gitlab` → `127.0.0.1:30481` | Web UI, API, **git smart HTTP** (`/info/refs`, `/git-upload-pack`, `/git-receive-pack`) |
| `registry.gitlab.lilangverse.xyz` | `proxy:gitlab` | Container registry via Omnibus |

All HTTP methods used by GitLab and git are proxied: `GET`, `HEAD`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`.

`[limits]` on the edge profile: `max_body = "512m"`, `proxy_max_response_body = "64m"` (LFS / large pushes).

## Fritz!Box (required)

Forward **only** to the edge IP — not the SSH/admin address:

| External | Internal | Target |
|----------|----------|--------|
| TCP **80** | **80** | **192.168.10.33** |
| TCP **443** | **443** | **192.168.10.33** |

Do **not** point port 80 at another host that returns a static `ok` page; **Let's Encrypt HTTP-01** and GitLab both need li-httpd on `:80` with `/.well-known/acme-challenge` routed.

Details: [fritz-klaut-pro-port-forward.md](fritz-klaut-pro-port-forward.md) (same IP rules for `*.klaut.pro` and `*.lilangverse.xyz`).

## TLS certificate

WAN HTTPS overlay ([gen-https-overlay.py](../k8s/edge/gen-https-overlay.py)) prefers, in order:

1. `homelab-edge` LE cert (all WAN hostnames)
2. Per-host LE cert at `/etc/letsencrypt/live/gitlab.lilangverse.xyz` (**SAN:** `gitlab.lilangverse.xyz`, `registry.gitlab.lilangverse.xyz`)
3. Partial `majico.d3bu7.com` cert (legacy fallback)

Issue or renew GitLab cert on blackpearl (HTTP-01 via li-httpd `:80`):

```bash
sudo certbot certonly --webroot -w /var/lib/li-httpd/acme \
  -d gitlab.lilangverse.xyz -d registry.gitlab.lilangverse.xyz
sudo bash ~/staging/homelab-k3s/scripts/edge-lis-apply.sh
sudo systemctl restart li-httpd-homelab.service li-httpd-homelab-tls.service
```

## Deploy / refresh edge

On blackpearl (after rsync `homelab-k3s`, `lic`, `li-httpd`):

```bash
cd ~/staging/homelab-k3s
bash scripts/build-edge-li-httpd.sh    # dynamic route table + edge patches
sudo bash scripts/edge-lis-apply.sh --install-systemd
sudo systemctl restart li-httpd-homelab.service
sleep 2
sudo systemctl restart li-httpd-homelab-tls.service
sudo systemctl enable --now li-httpd-edge-watchdog.timer
```

Requires `lic` on `feat/dynamic-httpd-routes` (or newer) — homelab flatten emits 200+ routes.

## Verify (no VPN)

From any external network:

```bash
# Web UI (expect 200 or 302 to sign-in)
curl -sS -o /dev/null -w 'sign_in=%{http_code}\n' https://gitlab.lilangverse.xyz/users/sign_in

# Git smart HTTP (private repo: 401 without token; public repo: 200 + refs)
curl -sS -o /dev/null -w 'git_refs=%{http_code}\n' \
  -H 'User-Agent: git/2.43.0' \
  'https://gitlab.lilangverse.xyz/li-langverse/lic.git/info/refs?service=git-upload-pack'

# Clone / ls-remote (use deploy token or credential helper for private repos)
GIT_TERMINAL_PROMPT=0 git ls-remote https://gitlab.lilangverse.xyz/li-langverse/lic.git
```

On blackpearl (always hits local li-httpd — use for edge debugging):

```bash
curl -skI -H 'Host: gitlab.lilangverse.xyz' https://127.0.0.1/users/sign_in
curl -skI -H 'Host: gitlab.lilangverse.xyz' \
  'https://127.0.0.1/li-langverse/lic.git/info/refs?service=git-upload-pack'
```

Hairpin from inside the LAN may differ from WAN; the edge watchdog probes with `--resolve gitlab.lilangverse.xyz:443:127.0.0.1` so restarts are not triggered by Fritz hairpin failures.

## Isolated acceptance before deploy

On blackpearl, stop the edge watchdog and kill orphan `/tmp/li-httpd` processes before testing. Rebuild with `build-edge-li-httpd.sh`, restart `li-httpd-homelab` then `li-httpd-homelab-tls`, then run **10× each** (**3s** spacing, **120s** curl timeout) for test **C** (local `--resolve`); with `/etc/hosts` on blackpearl mapping the public name to **`192.168.10.33`**, also run **10x** hostname HTTPS curls (split-DNS path):

| Test | Command pattern | Pass |
|------|-----------------|------|
| A | `curl -H 'Host: gitlab.lilangverse.xyz' http://127.0.0.1:30481/users/sign_in` + same-host CSS | sign 200/302, CSS **835437** bytes |
| B | same paths on `http://127.0.0.1:80` | same |
| C | `curl -k --resolve gitlab.lilangverse.xyz:443:127.0.0.1 https://gitlab.lilangverse.xyz/...` | same |

Require **local C = 10/10** and **hostname (split-DNS) = 10/10** (sign-in **200/302**, GitLab CSS **835437** bytes) before `edge-lis-apply.sh` or re-enabling `li-httpd-edge-watchdog.timer`. Acceptance gate runs on **blackpearl only** - not from a Windows workstation. If C or hostname curls fail, fix `lic`, rebuild on blackpearl only - do not deploy WAN probes in parallel with debug sessions.

## Emergency only — NodePort 30481

If the public hostname fails but GitLab is healthy in-cluster:

```bash
# LAN debug (not for normal developers)
curl -H 'Host: gitlab.lilangverse.xyz' http://192.168.10.33:30481/users/sign_in
git -c http.sslVerify=false ls-remote http://192.168.10.33:30481/li-langverse/lic.git
```

Do **not** publish NodePort 30481 on Fritz. Production path is always **443 → li-httpd → 30481**.

## Related

- [gitlab-homelab.md](gitlab-homelab.md) — Omnibus deploy, runner, backups
- [li-native-edge.md](li-native-edge.md) — edge policy, rebuild, watchdog
- [edge-ingress.md](edge-ingress.md) — topology and apply

## edge-lis-apply and loopback 000

`sudo diff` of `/run/li-httpd/homelab.runtime.conf` and `homelab.tls.runtime.conf` before vs after `edge-lis-apply.sh --render-only` is empty when TOML/lic flatten output is unchanged; post-apply loopback `000` is from li-httpd restart windows, not config drift. When runtime files are unchanged, `edge-lis-apply.sh` skips `systemctl restart`. Prefer `--render-only` or that skip path during watchdog/apply; restart only when flattened runtime changes or `/usr/local/bin/li-httpd` is rebuilt.

