# Public access — no VPN required

Developers worldwide use **`https://gitlab.lilangverse.xyz`** directly. **Production GitLab HTTPS** uses **nginx** on blackpearl (`192.168.10.33`); GitLab Omnibus stays on k3s NodePort **30481** — no second install, no VPN, no NodePort in normal workflows.

**li-httpd** remains in the stack for `:80` (ACME HTTP-01 + non-GitLab hostnames) and **`:8443` dev/benchmark** (full TLS overlay). Production edge stays **nginx :443** until an explicit cutover — li-httpd native relay is **TESTED** on `:8443` at lic **`606bf37ba`** (parallel 18/18 ×5, npm test:proxy 18/18, Playwright PASS).

## Path

```
Internet / developers
        │
        ▼
Fritz!Box WAN (77.23.124.82)  TCP 80 + 443  →  192.168.10.33 (blackpearl)
        │
        ├── :443  nginx (GitLab prod TLS)  ──►  127.0.0.1:30481
        ├── :80   li-httpd (ACME + other WAN/LAN hosts)
        └── :8443 li-httpd TLS overlay (dev / benchmark — TESTED @ lic 606bf37ba)
```

Registry (when enabled): `registry.gitlab.lilangverse.xyz` → same nginx upstream as web UI.

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

Do **not** point port 80 at another host that returns a static `ok` page; **Let's Encrypt HTTP-01** needs li-httpd on `:80` with `/.well-known/acme-challenge` routed (nginx uses the issued certs on `:443`).

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
sudo systemctl reload nginx-gitlab-edge.service
```

Certbot timer handles auto-renewal; reload nginx after renew (`certbot renew --deploy-hook "systemctl reload nginx-gitlab-edge"`).

## Deploy / refresh edge

On blackpearl (after rsync `homelab-k3s`):

```bash
cd ~/staging/homelab-k3s
sudo bash scripts/edge-nginx-apply.sh --install-systemd   # nginx :443 GitLab prod
sudo bash scripts/edge-lis-apply.sh --install-systemd     # li-httpd :80 + :8443 dev TLS
sudo systemctl enable --now li-httpd-edge-watchdog.timer
```

li-httpd dev rebuild (when iterating `lic` relay):

```bash
bash scripts/build-edge-li-httpd.sh
sudo bash scripts/edge-lis-apply.sh
sudo systemctl restart li-httpd-homelab.service li-httpd-homelab-tls.service
# Benchmark li-httpd on :8443 — production stays nginx :443
```

### li-httpd dev cutover path (`:8443` → `:443`)

When ready to move GitLab prod from nginx to li-httpd:

1. Confirm **TESTED** on `:8443` at the target lic SHA (currently **`606bf37ba`** on `main` after MR !128).
2. On blackpearl: `bash scripts/build-edge-li-httpd.sh` → `edge-lis-apply.sh` → restart `li-httpd-homelab-tls`.
3. Run [edge-acceptance-gate.sh](../scripts/edge-acceptance-gate.sh) with `EDGE_PROBE_RESOLVE=gitlab.lilangverse.xyz:8443:127.0.0.1` (and LAN resolve) — all parallel/sequential/CSS gates **18/18** and **10/10**.
4. Workstation: `npm test` in `homelab-k3s` (proxy + parallel + Playwright against `:443` nginx until cutover; use `:8443` resolve env for li-httpd-only gates).
5. **Cutover (manual only):** point Fritz `:443` at li-httpd (stop `nginx-gitlab-edge`, bind li-httpd `:443`, or swap upstream in nginx) — do **not** auto-switch; prod stays nginx until operator approves.

Merged relay fix: GitLab MR [li-langverse/lic!128](https://gitlab.lilangverse.xyz/li-langverse/lic/-/merge_requests/128) → `main` @ merge commit **`9f486a45`** (source **`606bf37ba`**).

## Public `li-langverse` repos (no sign-in)

As of **2026-06-10**, the **`li-langverse`** group and **66 of 67** projects are **public** — browse and `git clone` over HTTPS without login.

| Scope | Visibility | Notes |
|-------|------------|-------|
| Group `li-langverse` | **public** | [Explore](https://gitlab.lilangverse.xyz/explore) lists public projects |
| Li dev repos (`lic`, `lis`, `li-httpd`, …) | **public** | Primary GitLab source; GitHub org = **GHCR only** |
| `gitlab-homelab-config` | **private** | Homelab/k8s wiring — kept private (may reference cluster secrets) |
| `gitlab-github-mirror` | **public** | **Retired** — git mirror CronJob suspended; GHCR-only policy |

**Security:** public repos expose source and issue/MR metadata to the internet. Do not commit secrets, `.env`, or deploy tokens. Push still requires authentication (PAT or credential helper).

To re-apply visibility (admin PAT via `npm run gitlab:auth` / `scripts/gitlab-mint-pat.mjs`):

```bash
# Group (API may 500 — use rails runner on gitlab-0 if needed)
curl -sk -X PUT -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.lilangverse.xyz/api/v4/groups/4?visibility=public"

# Per project
curl -sk -X PUT -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
  "https://gitlab.lilangverse.xyz/api/v4/projects/<id>?visibility=public"
```

## Verify (no VPN)

From any external network (no `PRIVATE-TOKEN`):

```bash
# Explore / public project list
curl -sS 'https://gitlab.lilangverse.xyz/api/v4/projects?visibility=public&per_page=5'

# Public repo web UI (expect 200, not redirect to sign_in)
curl -sS -o /dev/null -w 'lic_web=%{http_code}\n' \
  https://gitlab.lilangverse.xyz/li-langverse/lic

# Git smart HTTP on public repo (expect 200 + refs)
curl -sS -o /dev/null -w 'git_refs=%{http_code}\n' \
  -H 'User-Agent: git/2.43.0' \
  'https://gitlab.lilangverse.xyz/li-langverse/lic.git/info/refs?service=git-upload-pack'

# Anonymous clone / ls-remote (public repos only)
GIT_TERMINAL_PROMPT=0 git ls-remote https://gitlab.lilangverse.xyz/li-langverse/lic.git

# Sign-in page still available for push/admin
curl -sS -o /dev/null -w 'sign_in=%{http_code}\n' https://gitlab.lilangverse.xyz/users/sign_in

# Private repo still gated (expect 302/401 without token)
curl -sS -o /dev/null -w 'homelab_config=%{http_code}\n' \
  https://gitlab.lilangverse.xyz/li-langverse/gitlab-homelab-config
```

On blackpearl (prod nginx :443; li-httpd dev :8443):

```bash
curl -skI --resolve gitlab.lilangverse.xyz:443:127.0.0.1 \
  https://gitlab.lilangverse.xyz/users/sign_in
curl -skI --resolve gitlab.lilangverse.xyz:443:127.0.0.1 \
  'https://gitlab.lilangverse.xyz/li-langverse/lic.git/info/refs?service=git-upload-pack'
# li-httpd dev overlay:
curl -skI --resolve gitlab.lilangverse.xyz:8443:127.0.0.1 \
  https://gitlab.lilangverse.xyz:8443/users/sign_in
```

Hairpin from inside the LAN may differ from WAN; the edge watchdog probes with `--resolve gitlab.lilangverse.xyz:443:127.0.0.1` so restarts are not triggered by Fritz hairpin failures.

## Acceptance gate (TESTED / NOT TESTED)

There is **no partial success**. Either the full gate passes on **blackpearl** or the edge is **NOT TESTED** — do not report fixed, merged, or deployed-success.

**TESTED** requires **all** of the following on blackpearl:

| Check | Requirement |
|-------|-------------|
| Parallel edge `127.0.0.1` | 18/18 sign_in CSS/JS assets (`200`, `size_download == Content-Length`, body not HTML) |
| Parallel edge `192.168.10.33` | 18/18 (same criteria, `--resolve gitlab.lilangverse.xyz:443:192.168.10.33`) |
| Sequential edge | 18/18 (same assets, one curl at a time) |
| CSS probe loopback | 10/10 via [edge-css-probe.sh](../scripts/edge-css-probe.sh) with `--resolve …:127.0.0.1` |
| CSS probe LAN | 10/10 via [edge-css-probe.sh](../scripts/edge-css-probe.sh) with `--resolve …:192.168.10.33` |

Run the combined gate: [scripts/edge-acceptance-gate.sh](../scripts/edge-acceptance-gate.sh). Parallel probe only: [scripts/edge-parallel-18-probe.sh](../scripts/edge-parallel-18-probe.sh).

**NOT TESTED** = any check below the above thresholds. Browser styling alone, sequential-only, or NodePort parallel success does **not** qualify.

Workstation `curl.exe` (Schannel) is not an acceptance probe for large TLS bodies. Acceptance gates run against **nginx :443** (production path). li-httpd `:8443` gates (relay development / pre-cutover) use `EDGE_PROBE_RESOLVE=gitlab.lilangverse.xyz:8443:192.168.10.33` — **TESTED** at lic **`606bf37ba`**.

## Isolated acceptance before deploy

On blackpearl, stop the edge watchdog before testing. With nginx on `:443`, run [scripts/edge-acceptance-gate.sh](../scripts/edge-acceptance-gate.sh). For li-httpd relay work, probe `:8443` instead (`EDGE_PROBE_RESOLVE=gitlab.lilangverse.xyz:8443:127.0.0.1`). The sequential CSS/JS checks (tests A–C below) remain useful for bisecting upstream vs edge; the **parallel 18/18** probes above are the hard gate.

| Test | Command pattern | Pass |
|------|-----------------|------|
| A | `curl -H 'Host: gitlab.lilangverse.xyz' http://127.0.0.1:30481/users/sign_in` + same-host CSS | sign 200/302, CSS **835437** bytes |
| B | same paths on `http://127.0.0.1:80` | same |
| C | `curl -k --resolve gitlab.lilangverse.xyz:443:127.0.0.1 https://gitlab.lilangverse.xyz/...` | same |

If any gate check fails on blackpearl, fix `lic`, rebuild on blackpearl only — do not deploy WAN probes in parallel with debug sessions.

## Emergency only — NodePort 30481

If the public hostname fails but GitLab is healthy in-cluster:

```bash
# LAN debug (not for normal developers)
curl -H 'Host: gitlab.lilangverse.xyz' http://192.168.10.33:30481/users/sign_in
git -c http.sslVerify=false ls-remote http://192.168.10.33:30481/li-langverse/lic.git
```

Do **not** publish NodePort 30481 on Fritz. Production path is always **443 → nginx → 30481**.

## Fast iteration (tokens, API bypass)

When edge POST/API writes fail but GitLab is healthy in-cluster: **[gitlab-fast-iteration.md](gitlab-fast-iteration.md)** (`npm run gitlab:auth`, NodePort bypass from blackpearl, Playwright session).

## Related

- [gitlab-homelab.md](gitlab-homelab.md) — Omnibus deploy, runner, backups
- [li-native-edge.md](li-native-edge.md) — edge policy, rebuild, watchdog
- [edge-ingress.md](edge-ingress.md) — topology and apply

## edge-lis-apply and loopback 000

`sudo diff` of `/run/li-httpd/homelab.runtime.conf` and `homelab.tls.runtime.conf` before vs after `edge-lis-apply.sh --render-only` is empty when TOML/lic flatten output is unchanged; post-apply loopback `000` is from li-httpd restart windows, not config drift. When runtime files are unchanged, `edge-lis-apply.sh` skips `systemctl restart`. Prefer `--render-only` or that skip path during watchdog/apply; restart only when flattened runtime changes or `/usr/local/bin/li-httpd` is rebuilt.

