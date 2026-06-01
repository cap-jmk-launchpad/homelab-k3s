# Homelab k3s security audit

**Date:** 2026-05-30  
**Scope:** LAN `192.168.10.0/24` — nodes blackpearl, engine, desktop, deck, anch0r  
**Method:** Non-destructive checks (curl, kubectl, SSH config review, TCP connect scans). No brute force, no pod deletion, no exploitation.  
**Context:** Run after deck/anch0r Pi OS upgrades. All five workers **Ready** as of 2026-05-30 follow-up. **deck** kernel upgraded to `6.12.87+rpt-rpi-v8`. **anch0r** UFW + loopback rule restored after reboot (`k3s-agent` active; LAN metrics ports open).

## Executive summary

The cluster core is in reasonable shape for a homelab: **anonymous Kubernetes API access is denied**, **kubelet read-only port 10255 is closed**, **embedded etcd is not exposed**, **SSH is key-only** on nodes we could inspect, and **Grafana default `admin/admin` does not work**. The main gaps are **network segmentation** (no NetworkPolicies, permissive UFW on the control plane, engine without UFW, anch0r without UFW) and **LAN-wide exposure of staging NodePorts and monitoring** on blackpearl. No committed secrets were found in git (only placeholders and docs).

**Auto-fixed in this audit:** documentation only (this file). Live remediation applied 2026-05-30 — see [Remediated](#remediated-2026-05-30).

---

## Findings by severity

### Critical

_None identified._ Anonymous API access and default Grafana credentials are not exploitable in current state.

### High

| ID | Finding | Evidence | Recommended fix |
|----|---------|----------|-----------------|
| H-1 | **k3s API (6443) UFW allows `Anywhere`** on blackpearl | `ufw status`: rule `[6] 6443/tcp ALLOW IN Anywhere` | Restrict to `192.168.10.0/24` (and VPN CIDR if used). **Ask before applying** — breaks off-LAN kubectl unless VPN. |
| H-2 | **Staging NodePorts open to `Anywhere` on blackpearl** | UFW rules `[2] 30080`, `[3] 30000` ALLOW Anywhere; TCP scan from workstation confirms OPEN on `.41` | Change UFW to LAN-only. Consider Ingress + auth instead of raw NodePort for staging. **Ask before changing** majico-staging exposure. |

### Medium

| ID | Finding | Evidence | Recommended fix |
|----|---------|----------|-----------------|
| M-1 | **No NetworkPolicies in cluster** | `kubectl get netpol -A` → no resources | Add default-deny + explicit allow for `majico-staging`, `monitoring`, `kube-system`. Start with staging namespace isolation. |
| M-2 | **engine: UFW inactive** | `ufw status` → inactive; ports 22, 80, 10250, 9100 OPEN from LAN scan | Enable UFW mirroring deck policy: 22, 9100, 10250 from `192.168.10.0/24` only. Review nginx on :80 purpose first. |
| M-3 | **anch0r: no UFW** | `ufw` not installed/active; 22, 80, 443, 10250, 9100 OPEN | Install/enable UFW: 22 + 80/443 (reverse proxy role) from LAN; 9100/10250 from LAN only. |
| M-4 | **Grafana NodePort 30300 reachable on LAN** | Workstation scan: `192.168.10.41:30300` OPEN; login page HTTP 200; anonymous `/api/org` → 401 | Acceptable for homelab if LAN-trusted. Rotate admin password periodically; remove `/tmp/monitoring-secrets.env` after noting password elsewhere. Not listed in UFW (kube-proxy path) — document intentional LAN access. |
| M-5 | **Grafana admin password stored in `/tmp`** | `/tmp/monitoring-secrets.env` mode `600`, owner `s4il0r` | Move to password manager; delete file on blackpearl when confirmed: `shred -u /tmp/monitoring-secrets.env`. |

### Low

| ID | Finding | Evidence | Recommended fix |
|----|---------|----------|-----------------|
| L-1 | **engine: stale SSH drop-in backup** | `/etc/ssh/sshd_config.d/99-headless.conf.bak` contains `PasswordAuthentication yes` (inactive `.bak`) | Remove backup file on engine to avoid accidental restore. |
| L-2 | **deck cordoned after upgrade** | `kubectl get nodes`: deck `SchedulingDisabled`; `unschedulable=true` | Uncordon when upgrade verified: `kubectl uncordon deck`. |
| L-3 | **deck OS upgrade incomplete** | deck kernel `6.6.74+rpt-rpi-v8` vs anch0r `6.12.25+rpt-rpi-v8` | Re-run OS upgrade/reboot on deck when convenient. |
| L-4 | **desktop: workstation SSH with homelab key failed** | `Permission denied (publickey)` to `192.168.10.31`; node Ready in cluster | Add workstation pubkey to desktop/WSL `authorized_keys` or use existing jump path. Only port 22 reachable from scan. |
| L-5 | **supabase-auth CrashLoopBackOff** | `majico-staging` pod restarts (availability, not direct exploit) | Fix staging secrets/config separately; do not change production secrets without documenting. |

### Info

| ID | Finding | Evidence |
|----|---------|----------|
| I-1 | k3s API rejects anonymous requests | `curl -sk https://127.0.0.1:6443/version` → 401 Unauthorized |
| I-2 | k3s node join token permissions OK | `/var/lib/rancher/k3s/server/token` → `600 root:root` |
| I-3 | TLS on API | CN=k3s, issuer k3s-server-ca, valid May 2026–May 2027 |
| I-4 | etcd not externally exposed | TCP 2379/2380 closed on all scanned nodes |
| I-5 | kubelet read-only port disabled | 10255 closed on blackpearl and anch0r |
| I-6 | SSH key-only (checked nodes) | blackpearl, engine, deck, anch0r: `PasswordAuthentication no` for `s4il0r`/`root` via Match blocks |
| I-7 | Grafana default creds changed | POST `admin/admin` → HTTP 400; anonymous API → 401 |
| I-8 | Git secret hygiene | `git grep` shows placeholders only; private keys excluded from tracked patterns |
| I-9 | RBAC baseline normal | `cluster-admin` bound to `system:masters` only; wildcard roles are standard controllers + prometheus operator |
| I-10 | NodePorts only on control-plane host in practice | Workstation scan: 30000/30080/30300 OPEN on `.41` only, not workers |

---

## Check results (detail)

### 1. k3s API (6443)

| Check | Result |
|-------|--------|
| Reachable from LAN | Yes — `.41:6443` OPEN from workstation and blackpearl |
| TLS | Present (k3s self-signed CA) |
| Anonymous auth | **Denied** (401) |
| Token file exposure | **600** on server only |

6443 reachable from all worker nodes (expected for k3s agents).

### 2. Grafana (30300)

| Check | Result |
|-------|--------|
| LAN exposure | NodePort OPEN on blackpearl |
| Default `admin/admin` | **Rejected** (HTTP 400) |
| Anonymous access | **Denied** (`/api/org` → 401) |
| Beyond LAN | Not tested (no WAN path assumed); treat NodePort as LAN-visible |

### 3. Services / NodePorts

```
majico-staging/majico-app-nodeport      3000:30080/TCP
majico-staging/supabase-kong-nodeport   8000:30000/TCP
monitoring/prometheus-stack-grafana     80:30300/TCP
```

All other services ClusterIP or internal. Postgres/redis/supabase remain cluster-internal (good).

### 4. SSH

| Node | Password auth | Root login | Notes |
|------|---------------|------------|-------|
| blackpearl | no | prohibit-password | OK |
| engine | no (Match s4il0r) | prohibit-password | stale `.bak` drop-in |
| deck | no | prohibit-password | OK |
| anch0r | no | prohibit-password | OK |
| desktop | not verified | not verified | pubkey from workstation failed |

### 5. UFW / firewall

| Node | Status | Notes |
|------|--------|-------|
| blackpearl | active | 6443, 30000, 30080, 80, 443 → **Anywhere**; 9100/10250 → LAN |
| deck | active | 22, 9100, 10250 (LAN); nginx 80/443 listening but **not** OPEN externally (UFW effective) |
| engine | **inactive** | 22, 80, 10250, 9100 OPEN on LAN |
| anch0r | **missing** | 22, 80, 443, 10250, 9100 OPEN on LAN |
| desktop | unknown | only 22 OPEN from scan |

### 6. Secrets in git (`beelink-cleanup`)

No live passwords, tokens, or private keys in tracked files. References are placeholders (`CHANGE_ME_DEPLOY_TIME`, `.env.example`, deploy scripts). Local key files `homelab`, `blackpearl`, `beelink` exist on disk — ensure they stay out of git (`.gitignore`).

### 7. RBAC

- Wildcard ClusterRoles present for expected components (`cluster-admin`, prometheus-stack-operator, kube controllers).
- No binding of `default` ServiceAccount to cluster-admin observed.
- `system:anonymous` cannot perform `SelfSubjectRulesReview`.

### 8. kubelet read-only port (10255)

Not listening on sampled nodes (blackpearl, anch0r).

### 9. etcd

Ports 2379/2380 closed on all nodes (k3s embedded etcd not exposed).

### 10. Network policies

None deployed. **majico-staging** shares the cluster network with monitoring and kube-system without L4 isolation.

### 11. Port scan summary (workstation → LAN)

| IP | Node | Notable OPEN ports |
|----|------|-------------------|
| 192.168.10.41 | blackpearl | 22, 6443, 30000, 30080, 30300, 9100, 10250 |
| 192.168.10.22 | anch0r | 22, 80, 443, 9100, 10250 |
| 192.168.10.26 | deck | 22, 9100, 10250 |
| 192.168.10.32 | engine | 22, 80, 9100, 10250 |
| 192.168.10.31 | desktop | 22 |
| 192.168.10.28 | macbook (client) | 22 |

---

## Top 5 findings (priority order)

1. **H-1** — k3s API UFW allows 6443 from Anywhere on blackpearl  
2. **H-2** — Staging NodePorts 30000/30080 UFW allows Anywhere  
3. **M-1** — No NetworkPolicies (no majico-staging isolation)  
4. **M-2/M-3** — engine UFW off; anch0r no UFW  
5. **M-4/M-5** — Grafana LAN-exposed via NodePort; password still in `/tmp/monitoring-secrets.env`

---

## Recommended fixes (safe order)

1. **Document & rotate Grafana password** — copy from `/tmp/monitoring-secrets.env` to a password manager, then shred the file.
2. **Tighten blackpearl UFW** — change 6443, 30000, 30080 from `Anywhere` to `192.168.10.0/24` (confirm VPN needs first).
3. **Enable UFW on engine and anch0r** — match deck worker template (22 + metrics from LAN; anch0r also 80/443).
4. **Add NetworkPolicies** — default-deny ingress in `majico-staging`, allow only required pod-to-pod paths.
5. **Uncordon deck** and **finish deck OS upgrade** when kernel matches anch0r.
6. **Remove** `99-headless.conf.bak` on engine.

---

## What was auto-fixed

| Action | Status |
|--------|--------|
| Created this audit report | Done |
| Live firewall changes | **Not applied** (requires approval) |
| NetworkPolicy manifests | **Not applied** (requires approval) |
| majico / production secrets | **Not touched** |
| Grafana password rotation | **Documented only** |

---

## Suggested UFW commands (review before running)

**blackpearl** — restrict API and staging (replace Anywhere rules):

```bash
sudo ufw delete allow 6443/tcp
sudo ufw delete allow 30000/tcp
sudo ufw delete allow 30080/tcp
sudo ufw allow from 192.168.10.0/24 to any port 6443 proto tcp comment 'k3s API LAN'
sudo ufw allow from 192.168.10.0/24 to any port 30000 proto tcp comment 'staging kong LAN'
sudo ufw allow from 192.168.10.0/24 to any port 30080 proto tcp comment 'staging app LAN'
```

**engine** (after confirming nginx :80 is intentional):

```bash
sudo ufw default deny incoming
sudo ufw allow OpenSSH
sudo ufw allow from 192.168.10.0/24 to any port 9100 proto tcp
sudo ufw allow from 192.168.10.0/24 to any port 10250 proto tcp
# optional: sudo ufw allow from 192.168.10.0/24 to any port 80 proto tcp
sudo ufw enable
```

---

## Re-run checklist

```bash
# From workstation with homelab key
ssh -i ./homelab s4il0r@192.168.10.41 kubectl get nodes
ssh -i ./homelab s4il0r@192.168.10.41 kubectl get netpol -A
ssh -i ./homelab s4il0r@192.168.10.41 sudo ufw status numbered
curl -sk -o /dev/null -w '%{http_code}\n' https://192.168.10.41:6443/version   # expect 401
curl -s -o /dev/null -w '%{http_code}\n' http://192.168.10.41:30300/api/org      # expect 401
```

Related: [homelab-monitoring.md](./homelab-monitoring.md)

---

## Remediated (2026-05-30)

Remediation applied from `beelink-cleanup` manifests and scripts. Staging and Grafana were verified reachable from the LAN after changes.

| ID | Action | Status |
|----|--------|--------|
| H-1 | blackpearl UFW: `6443` restricted to `192.168.10.0/24` | Done |
| H-2 | blackpearl UFW: `30000`, `30080` restricted to LAN | Done |
| M-1 | NetworkPolicies in `majico-staging` ([network-policies.yaml](../k8s/majico-staging/network-policies.yaml)) | Done |
| M-2 | engine UFW enabled (SSH, 80/9100/10250 from LAN) | Done |
| M-3 | anch0r UFW enabled (22, 80/443, 9100/10250 from LAN); loopback via `/etc/ufw/before.rules` + runtime `iptables -I INPUT 1 -i lo` for k3s | Done |
| M-4 | Grafana NodePort `30300` restricted on blackpearl UFW to LAN | Done |
| M-5 | `/tmp/monitoring-secrets.env` shredded; password documented via k8s secret in [homelab-monitoring.md](./homelab-monitoring.md) | Done |
| L-1 | Removed `99-headless.conf.bak` on engine | Done |
| L-2 | `kubectl uncordon deck` | Done |
| L-3 | deck OS/kernel upgrade to match anch0r | Done (`6.12.87+rpt-rpi-v8`; uncordoned) |
| L-4 | desktop metrics / SSH from LAN | **Partial** — WSL SSH via blackpearl jump `:2222` works; `netsh` LAN rules applied; `kubectl top node desktop` still blocked until **elevated** [windows-firewall-homelab-desktop-apply.ps1](../scripts/windows-firewall-homelab-desktop-apply.ps1) on the Windows host |
| L-5 | supabase-auth CrashLoopBackOff | **Not changed** (out of scope; no secret rotation) |

### Scripts and manifests added

- [scripts/homelab-security-ufw-blackpearl.sh](../scripts/homelab-security-ufw-blackpearl.sh)
- [scripts/homelab-security-ufw-engine.sh](../scripts/homelab-security-ufw-engine.sh)
- [scripts/homelab-security-ufw-anch0r.sh](../scripts/homelab-security-ufw-anch0r.sh)
- [k8s/majico-staging/network-policies.yaml](../k8s/majico-staging/network-policies.yaml)

### Wider LAN / VPN access later

If you need kubectl or staging NodePorts from outside `192.168.10.0/24`, add UFW rules on blackpearl, for example:

```bash
sudo ufw allow from <VPN_CIDR> to any port 6443 proto tcp comment 'k3s API VPN'
sudo ufw allow from <VPN_CIDR> to any port 30000 proto tcp comment 'staging kong VPN'
sudo ufw allow from <VPN_CIDR> to any port 30080 proto tcp comment 'staging app VPN'
sudo ufw allow from <VPN_CIDR> to any port 30300 proto tcp comment 'Grafana VPN'
```

### Post-remediation verification (2026-05-30)

| Check | Result |
|-------|--------|
| `http://192.168.10.41:30080/` | HTTP 200 |
| `http://192.168.10.41:30000/` | HTTP 404 (Kong up) |
| `http://192.168.10.41:30300/api/org` | HTTP 401 (auth required) |
| `kubectl get networkpolicy -n majico-staging` | 4 policies |
| `kubectl get node deck` unschedulable | false |
| anch0r `k3s-agent` | active |
| `kubectl top nodes` (5 nodes) | 4/5 (desktop pending Hyper-V firewall admin) |
| deck `df /` after podman prune + autoremove | ~47G used (was ~71G) |
| anch0r `df /` after autoremove | ~11G used (was ~12G) |
