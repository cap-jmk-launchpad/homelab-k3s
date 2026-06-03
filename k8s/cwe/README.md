# CWE mirror (MITRE catalog)

Lightweight **CWE taxonomy mirror** — not CVE search. Pulls official [MITRE `cwec_latest.xml.zip`](https://cwe.mitre.org/data/xml/cwec_latest.xml.zip), builds a JSON index, serves static files over HTTP.

| Item | Value |
|------|-------|
| Namespace | `cwe` (separate from `dependency-track`) |
| Node | `blackpearl` (~64 Mi nginx + periodic sync job) |
| NodePort | **30483** |
| Sync | CronJob every **10 minutes** (re-download only when zip SHA changes) |

Runbook: [docs/cwe-homelab.md](../../docs/cwe-homelab.md)

```bash
LAUNCHPAD_ENV=../.env ./scripts/k8s-cwe-secret.sh
./scripts/k8s-cwe-apply.sh
```

Endpoints (after first sync):

- `GET /manifest.json` — catalog version, SHA, sync time
- `GET /weaknesses.json` — id, name, abstraction, status
- `GET /cwec_latest.xml` — full MITRE XML
- `GET /health` — liveness
