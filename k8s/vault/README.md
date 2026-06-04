# Vault OSS + External Secrets (k3s)

Self-hosted Vault (namespace `vault`) and ESO manifests. See [docs/vault-homelab.md](../../docs/vault-homelab.md).

## Quick apply

```bash
./scripts/k8s-vault-oss-apply-remote.sh all
# or on blackpearl:
./scripts/k8s-vault-oss-apply.sh && ./scripts/k8s-vault-oss-init.sh
./scripts/hcp-vault-install-eso.sh
./scripts/hcp-vault-configure-k8s-auth.sh
./scripts/vault-oss-render-cluster-store.sh
kubectl apply -f external-secrets/cluster-secret-store.yaml
```

## Layout

| Path | Purpose |
|------|---------|
| `server/` | Vault OSS StatefulSet (Raft PVC, NodePort 30485) |
| `external-secrets/` | ESO namespace, RBAC, ClusterSecretStore template |
| `policies/` | Vault policy HCL (applied by configure script) |
| `projects/` | Per-product ExternalSecret manifests |

## ClusterSecretStore

- Name: **`homelab-vault`**

- Server: `http://vault.vault.svc:8200` (in-cluster; ESO uses K8s auth)



Legacy HCP store name was `hcp-vault` — OSS manifests use `homelab-vault`.

