# OWASP Dependency-Track on homelab k3s

Self-hosted **[OWASP Dependency-Track](https://dependencytrack.org/)** — component/SBOM analysis and vulnerability intelligence (NVD, GitHub Advisories, OSV, OSS Index, etc.). This is **not** a generic “OWASP database”; the product name is **Dependency-Track**.

Homelab layout matches GitLab/Supabase: dedicated namespace, launchpad `.env` credentials, NodePort on blackpearl, optional `*.klaut.pro` edge.

## RAM and placement

| Component | requests | limits | Notes |
|-----------|----------|--------|-------|
| API server (StatefulSet + `/data` PVC) | 2 Gi / 500m CPU | 4 Gi | Chart defaults are 5 Gi; tuned down for homelab |
| Frontend | 64 Mi / 150m | 128 Mi | Static UI |
| PostgreSQL 16 | 512 Mi / 100m | 1 Gi | PVC 10 Gi (`local-path`) |
| **Typical total** | ~2.5–3 Gi | ~5 Gi peak | First-time NVD/GHSA/OSV mirror spikes CPU/IO |

**Node:** Postgres, API server, and frontend use `nodeSelector: kubernetes.io/hostname: engine` (same idea as [gitlab-homelab.md](gitlab-homelab.md)). Relax selectors in `k8s/dependency-track/` if `engine` is unavailable.

## Access

| Mode | URL |
|------|-----|
| NodePort (LAN) | `http://192.168.10.33:30482/` |
| Port-forward | `kubectl -n dependency-track port-forward svc/dependency-track-frontend 8082:8080` |
| In-cluster API | `http://dependency-track-api-server.dependency-track.svc.cluster.local:8080` |

**First login:** `admin` / `admin` — you must change the password on first login ([upstream docs](https://docs.dependencytrack.org/getting-started/initial-startup/)).

## Vulnerability feed / mirror cadence

Dependency-Track runs **recurring mirror tasks** (NVD, GitHub Advisories, OSV, VulnDB, portfolio analysis). Details: [Recurring tasks](https://docs.dependencytrack.org/getting-started/recurring-tasks/).

### What “every 10 minutes” means here

| Expectation | Reality |
|-------------|---------|
| Poll mirrors every **10 minutes** | **Not supported** — `task-scheduler.*.mirror.cadence` values are **integers in hours** (minimum **1**). |
| Feeds update every 10 minutes | **No** — NVD/GitHub/OSV typically update on their own schedule (often hours). Shorter poll only checks sooner. |
| Homelab default | `DEPTRACK_MIRROR_CADENCE_HOURS=1` via `scripts/k8s-dependency-track-configure-feeds.sh` (after API key is set) |

After changing cadence, **restart the API server** (the configure script rolls the StatefulSet). First startup still runs a full initial mirror (often **10–30+ minutes**); do not kill the pod during that window.

### Enable GitHub Advisories

Turn on in **Administration → Analyzers → GitHub Advisories**, or let `k8s-dependency-track-configure-feeds.sh` set `vuln-source.github.advisories.enabled=true` when `DEPTRACK_API_KEY` is present. Optional PAT: `vuln-source.github.advisories.access.token` (rate limits without token).

### Optional NVD API key

Unauthenticated NVD REST mirroring is rate-limited. Request a key at [NVD API key form](https://nvd.nist.gov/developers/request-an-api-key) and set in the UI under NVD settings.

## Credentials (launchpad `.env`)

`scripts/k8s-dependency-track-secret.sh` writes/reuses (unless `DEPTRACK_REGENERATE_SECRETS=1`):

| Variable | Purpose |
|----------|---------|
| `DEPTRACK_NAMESPACE` | k8s namespace (`dependency-track`) |
| `DEPTRACK_NODEPORT` | Frontend NodePort (`30482`) |
| `DEPTRACK_PUBLIC_URL` | Optional public URL (edge) |
| `DEPTRACK_POSTGRES_PASSWORD` | Postgres user `dtrack` |
| `DEPTRACK_ALPINE_SECRET_KEY` | JWT signing key (also `secret.key` in k8s secret) |
| `DEPTRACK_MIRROR_CADENCE_HOURS` | Mirror poll interval in hours (default `1`) |
| `DEPTRACK_API_KEY` | Optional — automation API key for feed cadence script |

Never commit `.env`.

## Deploy

From homelab-k3s (or Windows with kubectl context to the cluster):

```bash
LAUNCHPAD_ENV=../.env ./scripts/k8s-dependency-track-secret.sh
./scripts/k8s-dependency-track-apply.sh
```

Remote (rsync + apply on blackpearl):

```bash
DEPTRACK_REMOTE=1 \
  STAGING_HOST=blackpearl \
  STAGING_KEY=/path/to/blackpearl \
  LAUNCHPAD_ENV=../.env \
  ./scripts/k8s-dependency-track-apply.sh
```

After first login and API key creation:

```bash
# Add DEPTRACK_API_KEY to launchpad .env, then:
LAUNCHPAD_ENV=../.env ./scripts/k8s-dependency-track-configure-feeds.sh
```

## Public edge (optional)

Suggested hostname: **`deps.klaut.pro`**.

1. Set `DEPTRACK_PUBLIC_URL=https://deps.klaut.pro` in launchpad `.env`.
2. Uncomment `dependency_track` upstream + `[[site]]` in [k8s/edge/homelab.httpd.toml](../k8s/edge/homelab.httpd.toml).
3. DNS **A** → WAN IP; Fritz **443** → `192.168.10.33`.
4. On blackpearl: rsync edge config, `bash scripts/edge-lis-apply.sh`.

## sec-agent (klaut.pro) integration

The **GitHub security agent** (`sec-agent`) can upload CycloneDX SBOMs to Dependency-Track and read findings for PR reviews. See [klaut-pro-products.md](klaut-pro-products.md). Store API URL + key in Vault `secret/saas/sec-agent/{env}/` when the product worker ships.

**CWE taxonomy** (weakness names, catalog version) is served separately by the lightweight [CWE mirror](cwe-homelab.md) — Dependency-Track vuln records may reference CWE ids but do not replace the full MITRE catalog cache.

## Coexistence with GitLab / Supabase

Separate namespace and NodePort **30482** (Supabase **30480**, GitLab **30481**). Watch total **engine** RAM if all three run together.

## Troubleshooting

```bash
kubectl -n dependency-track get pods,events
kubectl -n dependency-track logs statefulset/dependency-track-api-server -f
kubectl -n dependency-track logs statefulset/dependency-track-postgres
kubectl top pod -n dependency-track
```

- **Pending on engine:** relax `nodeSelector` or free memory.
- **API not ready:** wait for startup mirror; check apiserver logs for NVD rate limits.
- **UI 502:** confirm `frontend.apiBaseUrl` points at `dependency-track-api-server` service.
