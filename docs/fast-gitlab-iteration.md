# Fast GitLab iteration (Playwright auth + tokens)

Quick paths for homelab GitLab dev when edge asset relay is flaky. See [gitlab-fast-iteration.md](gitlab-fast-iteration.md) for API bypass and Omnibus notes.

## Quick reference

| Task | Command | Output |
|------|---------|--------|
| Mint PAT (fastest) | `npm run gitlab:mint-pat` | `.gitlab-token.local` |
| Browser session | `npm run gitlab:auth` | `.playwright/gitlab-session.json` |
| NodePort page load | `npm run gitlab:auth:nodeport` | session (POST may 422 — see below) |
| Login + PAT via UI | `npm run gitlab:auth:pat` | session + token (needs working edge POST) |
| Render gate | `npm run test:edge-gitlab-render` | `test-results/edge-gitlab-render/` |

## One-time setup (workstation)

```bash
cd homelab-k3s
npm install
npx playwright install chromium
```

Requires `KUBECONFIG=~/.kube/config-homelab`. Root password is read from `gitlab-secrets` at runtime — never committed.

## Playwright auth

```bash
cd homelab-k3s

# Edge HTTPS (default) — needs full asset relay for JS form
npm run gitlab:auth

# NodePort on engine — GET loads; POST login often 422 while external_url is HTTPS
npm run gitlab:auth:nodeport

# Prefer mint-pat when edge is NOT TESTED
npm run gitlab:mint-pat
```

### Gitignored outputs

| File | Purpose |
|------|---------|
| `.playwright/gitlab-session.json` | Playwright `storageState` |
| `.gitlab-token.local` | `GITLAB_TOKEN=glpat-…` |
| `test-results/gitlab-auth/summary.json` | Last login metadata |

### Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `GITLAB_HOST` | `gitlab.lilangverse.xyz` | Edge SNI |
| `EDGE_IP` | `192.168.10.33` | Chromium host MAP (edge) |
| `GITLAB_NODE_IP` | `192.168.10.32` | NodePort (engine) |
| `GITLAB_NODEPORT` | `30481` | GitLab NodePort |

## Typical loop (edge NOT TESTED)

```bash
cd homelab-k3s
npm run gitlab:mint-pat
source .gitlab-token.local
curl -sk --resolve gitlab.lilangverse.xyz:443:192.168.10.33 \
  -H "PRIVATE-TOKEN: $GITLAB_TOKEN" https://gitlab.lilangverse.xyz/api/v4/user
```

When [public-edge-gitlab.md](public-edge-gitlab.md) gate is **TESTED**, add `npm run test:edge-gitlab-render` and `npm run gitlab:auth`.

## Related

- [public-edge-gitlab.md](public-edge-gitlab.md) — acceptance gate
- [README-edge-gitlab-render.md](../scripts/README-edge-gitlab-render.md)
