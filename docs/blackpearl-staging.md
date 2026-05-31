# blackpearl — Majico staging ops (fresh install)

## Access

| Item | Value |
|------|--------|
| Host | `blackpearl` (set DHCP reservation in Fritz!box) |
| User | `s4il0r` |
| SSH key | `beelink-cleanup/beelink` |
| Sudo | **NOPASSWD** (after `scripts/setup-blackpearl-access.sh`) |

See [fresh-install-blackpearl.md](fresh-install-blackpearl.md) for clean Debian Trixie install.

## Staging source of truth

All majico staging config is in **majico.xyz**:

- `deploy/staging/` — compose, httpd TOML, bootstrap scripts

**Not** in `li/lis`.

## Tokens (local, never commit)

| Purpose | File |
|---------|------|
| GitHub clone | `Programming/li/.env.github` → `GH_TOKEN` |
| App secrets | `branding_saas_projects/.env.local` |
| Local env template | `beelink-cleanup/.env.example` |

## Server paths

| Path | Role |
|------|------|
| `/home/s4il0r/staging/majico.xyz` | Git clone |
| `/home/s4il0r/staging/supabase` | Official Supabase docker checkout |

## Deploy

**Edge ingress (homelab-wide):** [k8s/edge/README.md](../k8s/edge/README.md) — merges this repo's TOML with majico staging routes.

**Staging runbook:** majico.xyz `deploy/staging/docs/blackpearl-k8s-lis.md` (on host at `~/staging/majico.xyz`).

Legacy compose: `majico.xyz/deploy/staging/README.md`

