# step-ca (Homelab Internal CA)

[Smallstep step-ca](https://github.com/smallstep/certificates) issues TLS certificates for **LAN-only** names (`*.homelab.lan`, `ca.homelab.lan`) via **ACME**. Public `*.klaut.pro` hostnames stay on **Let's Encrypt via Caddy** — do not route WAN traffic here.

| Item | Value |
|------|-------|
| Namespace | `step-ca` |
| NodePort | **30484** (HTTPS / ACME) |
| In-cluster | `https://step-ca.step-ca.svc.cluster.local:9000` |
| ACME directory | `https://ca.homelab.lan/acme/acme/directory` (after LAN DNS + optional li-httpd proxy) |
| LAN debug | `https://192.168.10.33:30484/health` |

## Deploy

```bash
./scripts/k8s-step-ca-secret.sh
./scripts/k8s-step-ca-apply.sh

# From Windows workstation via blackpearl SSH:
STEP_CA_REMOTE=1 ./scripts/k8s-step-ca-apply.sh
```

## Export root CA (install on clients)

```bash
kubectl -n step-ca exec deploy/step-ca -- step ca root > homelab-root-ca.crt
# Or copy from PVC backup — see docs/internal-ca-homelab.md
```

## Backup

The PVC `step-ca-data` holds root/intermediate keys and the badger DB. **Loss = re-issue all internal certs.** See [docs/internal-ca-homelab.md](../../docs/internal-ca-homelab.md#backup-and-recovery).

## Related

- [docs/internal-ca-homelab.md](../../docs/internal-ca-homelab.md) — split DNS, Fritz!Box, client trust
- [k8s/edge/README.md](../edge/README.md) — WAN (Caddy/LE) vs LAN (li-httpd)
