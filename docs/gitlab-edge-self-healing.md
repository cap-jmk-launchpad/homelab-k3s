# GitLab edge self-healing (blackpearl)

> **Note:** the runtime probes here are now invoked by the **unified `cluster-watchdog`**
> timer (`scripts/cluster-watchdog.sh` → `heal_edge`), which also covers li-httpd, the
> portfolio, cluster service keep-up, container prune and backup rotation. The
> standalone `gitlab-edge-watchdog.timer` is retired; see
> [docs/cluster-watchdog.md](cluster-watchdog.md). `gitlab-edge-watchdog.sh` is retained
> only as the GitLab-specific upstream/pod healer that `cluster-watchdog` calls.

When **engine** reboots, DHCP may change its k3s `InternalIP` (e.g. `192.168.10.32` to `192.168.10.40`).
nginx on blackpearl can keep proxying to a stale LAN IP while GitLab Omnibus on NodePort
**30481** is healthy on the cluster.

## gitlab-edge-watchdog

Systemd timer on blackpearl (every 3 minutes):

1. Probe `https://gitlab.lilangverse.xyz/users/sign_in` via local nginx (`--resolve` to `127.0.0.1:443`).
2. Read **engine** `InternalIP` from the k3s API.
3. On repeated failure: probe `127.0.0.1:30481` then `engine:30481`, patch `/etc/nginx/gitlab-edge/nginx.conf` upstream, reload nginx.
4. If NodePort works but nginx still fails: delete **gitlab-0** when the pod is not Ready (StatefulSet recreates it).
5. Last resort: [gitlab-engine-tunnel-recovery.sh](../scripts/gitlab-engine-tunnel-recovery.sh) (reverse SSH to `127.0.0.1:30581`).

When healthy, prefer upstream `127.0.0.1:30481` (cluster NodePort on blackpearl) over a pinned engine LAN IP.

### Install

Install the unified watchdog (covers GitLab edge healing + all other keep-up duties):

```bash
cd ~/staging/homelab-k3s
sudo bash scripts/deploy-cluster-watchdog.sh
```

This arms `cluster-watchdog.timer` (every 5 min) and retires the old
`li-httpd-edge-watchdog.timer` + `gitlab-edge-watchdog.timer`.


### Logs

| Location | Purpose |
|----------|---------|
| `/var/log/gitlab-edge-watchdog.log` | Action log with timestamps |
| `journalctl -u gitlab-edge-watchdog.service` | systemd oneshot output |
| `/run/gitlab-edge-watchdog/fail-streak` | Consecutive local probe failures before heal |

Manual run: `sudo /usr/local/bin/gitlab-edge-watchdog.sh`

See also [public-edge-gitlab.md](public-edge-gitlab.md).