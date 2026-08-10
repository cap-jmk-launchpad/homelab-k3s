# Librebase todo-app (todo.librebase.xyz)

Public demo of the Librebase stack: a todo app with auth + CRUD served over the
homelab edge.

| Item | Value |
|------|-------|
| URL | `https://todo.librebase.xyz` |
| Namespace | `librebase` |
| Image | `docker.io/library/librebase-todo:latest` (sideloaded, `imagePullPolicy: Never`) |
| NodePort | `30500` (pinned to node `engine`, amd64) |
| Containers | `lis` (mock auth + in-memory REST, :54321) + `todo-app` (:8787) |
| Source | `li-langverse/librebase` → `apps/todo-app/`, `deploy/docker/librebase-todo/` |

## Architecture

```
Internet → FritzBox WAN (77.23.124.82) → blackpearl
  ├─ :443 nginx-gitlab-edge → NodePort 30500 → todo-app :8787
  └─ :80  li-httpd / nginx default → li-httpd :8080 → upstream librebase_todo → NodePort 30500
```

DNS: `A todo.librebase.xyz → 77.23.124.82` (IONOS zone `librebase.xyz`).

TLS: Let's Encrypt cert `todo.librebase.xyz` (webroot `/var/lib/li-httpd`), served
by `nginx-gitlab-edge` (`nginx-todo-librebase-xyz.conf`).

## Deploy

```bash
bash scripts/deploy-librebase-todo.sh
```

Syncs `apps/todo-app`, `packages/sdk`, `lis`, and the Dockerfile to engine
(`s4il0r@192.168.10.40`), builds `librebase-todo:latest` there, imports it into
k3s containerd (`/run/k3s/containerd/containerd.sock`), and applies
`k8s/librebase-todo/todo-app.yaml`.

## Edge routes

- li-httpd: `[[upstreams.librebase_todo]]` → `127.0.0.1:30500` + `[[site]] todo.librebase.xyz`
  in `k8s/edge/homelab.httpd.toml`.
- nginx :443: `k8s/edge/nginx-todo-librebase-xyz.conf` (included from `nginx-gitlab-edge`).
- ACME HTTP-01: served by nginx default `:80` server from `/var/lib/li-httpd`.

## Smoke

```bash
curl -s https://todo.librebase.xyz/health            # {"ok":true,"service":"todo-app"}
curl -s https://todo.librebase.xyz/                  # web UI (signup/signin + todos)
curl -s -X POST https://todo.librebase.xyz/auth/signup -H 'Content-Type: application/json' \
  -d '{"email":"a@example.com","password":"secret-pass"}'
```

Note: `lis` runs with **mock auth + in-memory REST** — state is not durable across
pod restarts. It is a demo, not a production data plane.
