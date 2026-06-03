# MITRE CWE mirror on homelab k3s

Self-hosted **CWE (Common Weakness Enumeration) taxonomy** for agents and review tools. This is **not** a CVE database — use [Dependency-Track](dependency-track-homelab.md) for SBOM/CVE findings and [cve-search](https://github.com/cve-search/cve-search) only if you need a full MongoDB CVE corpus (heavy; overlaps Dependency-Track for PR workflows).

## Why `cwe-mirror` (not cve-search)

| Option | Fit for CWE taxonomy | Homelab cost |
|--------|----------------------|--------------|
| **cwe-mirror** (chosen) | Official MITRE `cwec_latest.xml.zip` + JSON index | ~64 Mi nginx + brief sync bursts on **blackpearl** |
| **MITRE CWE REST API** | Live JSON per weakness; MITRE recommends local cache | No deploy; rate/availability external |
| **cve-search** | CVE + CWE expansion on CVE records | MongoDB + Redis; multi-GB; belongs on **engine** |
| **OpenCVE** | CVE-centric | Heavier stack; CWE is secondary |

MITRE publishes CWE catalog updates on a **release cadence** (roughly monthly), not every 10 minutes. The homelab CronJob still runs **every 10 minutes** but only re-downloads and re-indexes when the zip **SHA-256** changes — matching the “poll often, work only when upstream changed” model used for Dependency-Track mirrors.

## RAM and placement

| Component | requests | limits | Node |
|-----------|----------|--------|------|
| nginx static server | 25m / 32 Mi | 128 Mi | `blackpearl` |
| sync CronJob | 50m / 128 Mi | 512 Mi | `blackpearl` |
| PVC | — | 2 Gi `local-path` | — |

No `engine` placement — intentionally light. Dependency-Track stays on **engine** ([dependency-track-homelab.md](dependency-track-homelab.md)).

## Access

| Mode | URL |
|------|-----|
| NodePort (LAN) | `http://192.168.10.33:30483/manifest.json` |
| In-cluster | `http://cwe-mirror.cwe.svc.cluster.local:8080/` |
| Port-forward | `kubectl -n cwe port-forward svc/cwe-mirror 8083:8080` |

### HTTP API (static files)

| Path | Content |
|------|---------|
| `/health` | `ok` |
| `/manifest.json` | Catalog version, SHA, `synced_at`, link to MITRE REST |
| `/weaknesses.json` | Array of `{id, name, abstraction, status, structure}` |
| `/cwec_latest.xml` | Full MITRE XML (same as upstream zip) |

For rich weakness text (descriptions, relationships), use MITRE REST after resolving id from `weaknesses.json`:

`https://cwe-api.mitre.org/api/v1/cwe/weakness/{id}` (no API key).

## Sync schedule

| Setting | Default |
|---------|---------|
| CronJob | `*/10 * * * *` |
| Override | `CWE_SYNC_SCHEDULE` in launchpad `.env` (patch applied by apply script) |
| Source | `CWE_SOURCE_URL` → `https://cwe.mitre.org/data/xml/cwec_latest.xml.zip` |

## Credentials (launchpad `.env`)

`scripts/k8s-cwe-secret.sh` writes/reuses (unless `CWE_REGENERATE_SECRETS=1`):

| Variable | Purpose |
|----------|---------|
| `CWE_NAMESPACE` | k8s namespace (`cwe`) |
| `CWE_NODEPORT` | NodePort (`30483`) |
| `CWE_PUBLIC_URL` | Optional public URL (edge) |
| `CWE_SOURCE_URL` | MITRE zip URL |
| `CWE_SYNC_SCHEDULE` | Cron expression |
| `CWE_MIRROR_API_TOKEN` | Optional bearer for future edge auth / Vault seed |

Never commit `.env`. The mirror is **unauthenticated** on the cluster network today; keep WAN behind edge or network policy.

## Deploy

```bash
LAUNCHPAD_ENV=../.env ./scripts/k8s-cwe-secret.sh
./scripts/k8s-cwe-apply.sh
```

Remote (rsync + apply on blackpearl):

```bash
CWE_REMOTE=1 \
  STAGING_HOST=blackpearl \
  STAGING_KEY=/path/to/blackpearl \
  LAUNCHPAD_ENV=../.env \
  ./scripts/k8s-cwe-apply.sh
```

Verify:

```bash
curl -s http://192.168.10.33:30483/manifest.json | head
curl -s http://192.168.10.33:30483/weaknesses.json | head -c 400
```

## Overlap with Dependency-Track

| Data | Dependency-Track | CWE mirror |
|------|------------------|------------|
| CVE / CVSS / affected components | Yes (mirrors) | No |
| CWE ids on vulnerabilities | Often in finding metadata | No live CVE feed |
| Full CWE taxonomy (names, catalog version, XML) | Partial via vuln records | Yes — purpose-built |
| SBOM upload / portfolio | Yes | No |

**Still valuable for sec-agent:** PR reviews need stable **CWE id → name/category** lookups and offline-friendly bulk JSON without scraping MITRE on every comment. Dependency-Track does not replace a dedicated CWE catalog cache.

## sec-agent (klaut.pro)

Store homelab mirror base URL in Vault `secret/saas/sec-agent/{env}/`:

- `CWE_MIRROR_URL` — e.g. `http://cwe-mirror.cwe.svc.cluster.local:8080`
- `CWE_MIRROR_API_TOKEN` — optional if edge enforces bearer

Product matrix: [klaut-pro-products.md](klaut-pro-products.md). SBOM/CVE path remains Dependency-Track (`DEPTRACK_*` in the same doc family).

## Public edge (optional)

Suggested hostname: **`cwe.klaut.pro`**.

1. Set `CWE_PUBLIC_URL=https://cwe.klaut.pro` in launchpad `.env`.
2. Uncomment `cwe_mirror` upstream + `[[site]]` in [k8s/edge/homelab.httpd.toml](../k8s/edge/homelab.httpd.toml).
3. DNS **A** → WAN IP; Fritz **443** → `192.168.10.33`.
4. On blackpearl: rsync edge config, `bash scripts/edge-lis-apply.sh`.

## Coexistence

Homelab NodePort matrix (all deployed on blackpearl): [klaut-pro-products.md](klaut-pro-products.md#homelab-inventory-current).

| Service | Namespace | NodePort | WAN |
|---------|-----------|----------|-----|
| SearXNG | `searxng` | 30479 | `search.klaut.pro` (live) |
| Supabase | `supabase` | 30480 | internal only |
| GitLab | `gitlab` | 30481 | `gitlab.klaut.pro` optional |
| Dependency-Track | `dependency-track` | 30482 | `deps.klaut.pro` optional |
| **CWE mirror** | `cwe` | **30483** | `cwe.klaut.pro` optional |

## Troubleshooting

```bash
kubectl -n cwe get pods,events,cronjob,job
kubectl -n cwe logs deployment/cwe-mirror
kubectl -n cwe logs job -l component=sync --tail=100
kubectl -n cwe exec deploy/cwe-mirror -- ls -la /data/public
```

- **404 on manifest:** wait for sync job; check CronJob/job logs for curl/unzip errors.
- **Pending PVC:** ensure `local-path` provisioner on blackpearl.
- **MITRE download failures:** transient; job retries on next 10-minute tick.
