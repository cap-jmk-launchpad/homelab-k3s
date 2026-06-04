# GitLab CE on homelab k3s

Omnibus **GitLab CE** in namespace `gitlab`, **NodePort 30481** (HTTP) / **30222** (git SSH). GitLab Runner uses the **kubernetes** executor in the same namespace.

See [docs/gitlab-homelab.md](../../docs/gitlab-homelab.md) for setup checklist, persistence, backups, and credentials.

```bash
LAUNCHPAD_ENV=../.env ./scripts/k8s-gitlab-secret.sh
./scripts/k8s-gitlab-apply.sh
./scripts/k8s-gitlab-backup.sh      # on-demand
./scripts/k8s-gitlab-restore.sh     # list / restore
```

PVCs: `gitlab-data` (repos + DB), `gitlab-runner-config`, `gitlab-backups` (weekly tarball copies).
