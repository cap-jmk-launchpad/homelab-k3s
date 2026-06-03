# ESO bootstrap role — read all saas/* paths (homelab pragmatic).
# Applied by scripts/hcp-vault-configure-k8s-auth.sh

path "secret/data/saas/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/saas/*" {
  capabilities = ["read", "list"]
}
