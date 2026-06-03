# Per-project/env policy template.
# Placeholders: PROJECT, ENV — replaced by hcp-vault-onboard-project.sh

path "secret/data/saas/PROJECT/ENV" {
  capabilities = ["read"]
}

path "secret/data/saas/PROJECT/ENV/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/saas/PROJECT/ENV" {
  capabilities = ["read"]
}

path "secret/metadata/saas/PROJECT/ENV/*" {
  capabilities = ["read", "list"]
}
