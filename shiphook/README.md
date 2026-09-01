# Shiphook deploy-webhook gateway (blackpearl:3141)

Live config (source of truth): `/home/s4il0r/staging/shiphook-server/shiphook.yaml`
Secret (local only, NOT committed): `/home/s4il0r/staging/shiphook-server/.shiphook.staging.secret`
Service: `shiphook-staging.service` (node $(which shiphook))

## This directory
- `shiphook.yaml` — git-tracked snapshot for restore + drift detection.
- `restore.sh` — restore config from this repo or newest backup + restart service.

## Restore procedure (manual)
SSH blackpearl then:
```bash
bash /home/s4il0r/homelab-k3s/shiphook/restore.sh
```

## Backups
- On-demand: `sudo tar -czf /home/s4il0r/backups/shiphook-\$(date -u +%Y%m%dT%H%M%SZ).tar.gz -C /home/s4il0r/staging shiphook-server/`
- Watchdog auto-creates one on first heal if `/home/s4il0r/backups/shiphook-*.tar.gz` is missing.
- Watchdog `check_shiphook()` in scripts/cluster-watchdog.sh streak>=2 restores + restarts.

## Routed webhooks (canonical host per docs/obsevia-demo-ci-shiphook.md)
POST https://hook.obsevia.d3bu7.com/deploy/staging/{qroma|ducah|dp}
POST https://hook.agentic-book.org/deploy/agentic-book
