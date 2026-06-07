# Agent guide — homelab-k3s

## Platform policy (read first)

- **[docs/li-native-edge.md](docs/li-native-edge.md)** — Li-native edge: **li-httpd only** for all HTTP(S) ingress
- **[docs/platform-requirements.md](docs/platform-requirements.md)** — Linux hosts, NodePort backends, Windows scope

Run before finishing edge or routing changes:

```bash
bash scripts/lint-li-native.sh
```

## Repository layout

| Path | Purpose |
|------|---------|
| `k8s/` | Kubernetes manifests — workloads, NodePort services |
| `k8s/edge/` | Li-native edge config (`homelab.httpd.toml`); legacy in `deprecated/` |
| `scripts/` | Bash apply/validate on Linux; `windows-*.ps1` is desktop-only |
| `docs/` | Deployment and ops documentation |

## Edge ingress rules

1. k3s installs with **`--disable traefik`** ([docs/k3s-server.md](docs/k3s-server.md)).
2. Do **not** add `kind: Ingress`, Traefik, Caddy, or `LoadBalancer` services for HTTP exposure.
3. All routes → `k8s/edge/homelab.httpd.toml` → `scripts/edge-lis-apply.sh` on blackpearl.
4. In-cluster Kong/nginx (Supabase, CWE, GitLab) is application-level — not cluster ingress.

## Adding a service to the edge

1. NodePort in `k8s/<stack>/`.
2. Upstream + `[[site]]` in `homelab.httpd.toml`.
3. `lint-li-native.sh` + `edge-lis-validate.sh`.
4. Update [docs/klaut-pro-products.md](docs/klaut-pro-products.md).

## Windows vs Linux

- **blackpearl, control plane, workers:** Debian/Ubuntu only.
- **desktop:** WSL2 k3s agent; Windows scripts are firewall/tray helpers — not edge.
- Edge uses Linux paths (`/usr/local/bin/li-httpd`, `systemctl`, `ufw`).

## Cursor rules

- `.cursor/rules/homelab-edge-platform.mdc` — Li-native edge policy
- `.cursor/rules/protect-local-secrets.mdc` — never delete/move SSH keys, `.env`, or kubeconfig on the Windows client

User-level hook: `%USERPROFILE%\.cursor\hooks.json` blocks destructive commands on secret paths (all projects).
