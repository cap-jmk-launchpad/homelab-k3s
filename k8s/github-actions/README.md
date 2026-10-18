# GitHub Actions runners on homelab k3s

Ephemeral **Actions Runner Controller (ARC)** scale sets on the **engine** node, one per product org. Workflows opt in with `runs-on` labels (see [docs/github-actions-homelab-runners.md](../../docs/github-actions-homelab-runners.md)).

| Org | `githubConfigUrl` | Workflow labels |
| --- | --- | --- |
| Majico | `https://github.com/majico-xyz` | `self-hosted`, `majico-staging`, `linux` |
| Librebase | `https://github.com/librebase-official` | `self-hosted`, `librebase-homelab`, `linux` |
| Obsevia | `https://github.com/obsevia-compliance` | `self-hosted`, `obsevia-homelab`, `linux` |

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

GitHub → org **Settings → Actions → Runners** should list scale sets `majico-homelab`, `librebase-homelab`, `obsevia-homelab`.

Controller namespace: `arc-systems`. Runner pods: `github-actions`.
