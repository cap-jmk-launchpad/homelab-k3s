# GitLab edge render tests (Playwright + curl 18/18)

Verifies `https://gitlab.lilangverse.xyz/users/sign_in` renders correctly through **li-httpd** on blackpearl (`192.168.10.33`). Both probes must pass for **STATUS: TESTED**.

## Prerequisites

- Node.js 18+
- Google Chrome (Playwright uses `channel: chrome`)
- `curl` (Git Bash / WSL on Windows, or `curl.exe` via PowerShell script)

## Install

```bash
cd homelab-k3s
npm install
npx playwright install chrome   # optional if system Chrome is present
```

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `GITLAB_HOST` | `gitlab.lilangverse.xyz` | Host header / SNI |
| `EDGE_IP` | `192.168.10.33` | `--resolve` / Chromium host-resolver MAP target |

LAN split-DNS or hosts entry pointing the hostname at `192.168.10.33` is equivalent to `--resolve`.

## Run full edge suite

```bash
npm test                  # proxy + parallel + render
npm run test:proxy        # curl 18/18 (wc -c gate)
npm run test:edge-parallel  # parallel 18/18
npm run test:edge-render  # Playwright
```

## Run Playwright (browser render)

```bash
npm run test:edge-render
# or
npx playwright test edge-gitlab-render
```

Artifacts: `test-results/edge-gitlab-render/gitlab-sign-in.png`, `summary.json`.

## Run parallel curl asset gate (18/18)

**Linux / blackpearl / Git Bash:**

```bash
npm run test:proxy
# or
bash scripts/edge-gitlab-assets-curl.sh
```

**Windows PowerShell:**

```powershell
.\scripts\edge-gitlab-assets-curl.ps1
```

Exit code `0` only when every CSS/JS asset from sign_in HTML returns HTTP 200, `Content-Length` matches downloaded bytes, and body does not start with `<` (HTML error page).

## Strict acceptance

| Gate | Pass criterion |
|------|----------------|
| Playwright | CSS + JS loaded (200, non-zero), logo visible, form styled, no truncation, no console errors |
| curl parallel | `RESULT parallel-edge: N/N` where N = all `/assets/*.css` and `/assets/*.js` on sign_in |

Workstation `curl.exe` (Schannel) may truncate large TLS bodies; if curl fails on Windows but Playwright passes, re-run curl on **blackpearl** with the bash script. Playwright uses Chromium TLS and is the authoritative browser render check.

## Related

- [public-edge-gitlab.md](../docs/public-edge-gitlab.md) — edge topology
- [edge-css-probe.sh](./edge-css-probe.sh) — 10× CSS size probe on blackpearl
