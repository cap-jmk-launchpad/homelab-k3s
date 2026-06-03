# HCP Vault + External Secrets (k3s)

Sync secrets from HCP Vault Dedicated into Kubernetes Secrets. See [docs/hcp-vault.md](../../docs/hcp-vault.md) for portal setup and onboarding.

## Quick apply

```bash
./scripts/hcp-vault-install-eso.sh
./scripts/hcp-vault-configure-k8s-auth.sh   # requires VAULT_ADDR + VAULT_TOKEN in .env

cp external-secrets/cluster-secret-store.example.yaml external-secrets/cluster-secret-store.yaml
# edit server URL, then:
kubectl apply -f external-secrets/namespace.yaml
kubectl apply -f external-secrets/eso-rbac.yaml
kubectl apply -f external-secrets/cluster-secret-store.yaml
```

## Layout

| Path | Purpose |
|------|---------|
| `external-secrets/` | ESO namespace, RBAC, ClusterSecretStore template |
| `policies/` | Vault policy HCL (reference; applied by configure script) |
| `projects/agent-swarm/` | ExternalSecret for agent-swarm |
| `projects/majico-staging/` | ExternalSecret for majico staging |
| `projects/sec-agent/` | GitHub security agent (klaut.pro) |
| `projects/search-gateway/` | Search API (`search-api` slug) |
| `projects/klaut-platform/` | Vault API control plane (`vault-api` slug) |

## Secret paths (KV v2, mount `secret`)

```
saas/{project}/{env}     →  keys become K8s secret data
saas/_shared/homelab     →  optional cross-project keys
```

## Per-project ExternalSecret

Copy an example, customize keys, apply:

```bash
./scripts/hcp-vault-onboard-project.sh majico staging majico-staging
kubectl apply -f projects/majico-staging/external-secret.yaml
```

Klaut product manifests are committed under `projects/sec-agent`, `search-gateway`, `klaut-platform`. Other projects may use `.example.yaml` only — run `hcp-vault-onboard-project.sh` to generate `external-secret.yaml`.
