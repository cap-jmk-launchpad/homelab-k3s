# GitHub Actions runners on homelab k3s

Ephemeral **Actions Runner Controller (ARC)** scale sets on the **engine** node only — never on MacBook or other laptops. One scale set per product org. Workflows opt in with `runs-on` labels (see [docs/github-actions-homelab-runners.md](../../docs/github-actions-homelab-runners.md)).

| Org | `githubConfigUrl` | Workflow `runs-on` |
| --- | --- | --- |
| cap-jmk-launchpad | `https://github.com/cap-jmk-launchpad` | `home-k3s` (also `self-hosted`, `linux`) |
| Majico | `https://github.com/majico-xyz` | `home-k3s` (+ `majico-staging` where wired) |
| Librebase | `https://github.com/librebase-official` | `home-k3s` (+ `librebase-homelab` where wired) |
| Obsevia | `https://github.com/obsevia-compliance` | `home-k3s` (+ `obsevia-homelab` where wired) |
| sailblack | `https://github.com/sailblack` | `home-k3s` |
| taktwerk | `https://github.com/taktwerk` | `home-k3s` |

## Bootstrap

```bash
# Tokens in launchpad .env (see scripts/k8s-github-actions-secret.sh)
LAUNCHPAD_ENV=../.env ./scripts/k8s-github-actions-secret.sh
./scripts/k8s-github-actions-apply.sh
```

Remote apply (same pattern as GitLab):

```bash
GITHUB_ACTIONS_REMOTE=1 STAGING_HOST=blackpearl ./scripts/k8s-github-actions-apply.sh
```

## Verify

```bash
kubectl get autoscalingrunnersets -n github-actions
kubectl get pods -n github-actions
kubectl get pods -n arc-systems
```

GitHub → org **Settings → Actions → Runners** should list scale set **`home-k3s`** (runner group `homelab-k3s`) for each org.

Controller namespace: `arc-systems`. One scale-set namespace per org: `gha-<org>` (e.g. `gha-majico-xyz`).

Enable all repos in an org: `./scripts/k8s-github-actions-org-enable.sh` then use `runs-on: home-k3s` in workflows.
