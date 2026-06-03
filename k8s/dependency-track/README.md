# OWASP Dependency-Track (homelab k3s)

**OWASP Dependency-Track** — SBOM ingestion and vulnerability intelligence (NVD, GitHub Advisories, OSV, OSS Index, etc.). Not a generic “OWASP database.”

| Piece | Detail |
|-------|--------|
| Namespace | `dependency-track` |
| Postgres | `dependency-track-postgres` StatefulSet (PVC 10Gi) |
| API + UI | Official [Helm chart](https://github.com/DependencyTrack/helm-charts) release `dependency-track` |
| NodePort | **30482** → frontend (UI talks to in-cluster API) |
| Node | `engine` (RAM-heavy; same pattern as GitLab) |

Runbook: [docs/dependency-track-homelab.md](../../docs/dependency-track-homelab.md)

```bash
LAUNCHPAD_ENV=../.env ./scripts/k8s-dependency-track-secret.sh
./scripts/k8s-dependency-track-apply.sh
```
