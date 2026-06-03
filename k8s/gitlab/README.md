# GitLab CE on homelab k3s

Omnibus **GitLab CE** in namespace `gitlab`, **NodePort 30481** (HTTP) / **30222** (git SSH). GitLab Runner uses the **kubernetes** executor in the same namespace.

See [docs/gitlab-homelab.md](../../docs/gitlab-homelab.md) for RAM, engine placement, edge, and credentials.

```bash
LAUNCHPAD_ENV=../.env ./scripts/k8s-gitlab-secret.sh
./scripts/k8s-gitlab-apply.sh
```
