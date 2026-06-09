#!/usr/bin/env bash
# Regenerate CI JWT / job-token signing keys when GitLab logs show:
#   OpenSSL::Cipher::CipherError in lib/ci/job_token/jwt.rb
# Causes scheduler_failure on all CI jobs after gitlab-secrets.json rotation.
set -euo pipefail

NAMESPACE="${GITLAB_NAMESPACE:-gitlab}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1" >&2; exit 1; }; }
require_cmd kubectl

echo "==> Clear corrupted signing key columns"
kubectl exec -n "$NAMESPACE" gitlab-0 -- gitlab-psql -d gitlabhq_production -c \
  "UPDATE application_settings SET encrypted_ci_jwt_signing_key = NULL, encrypted_ci_jwt_signing_key_iv = NULL, encrypted_ci_job_token_signing_key = NULL, encrypted_ci_job_token_signing_key_iv = NULL, runners_registration_token_encrypted = NULL;"

echo "==> Write fresh RSA signing keys (bypass AR callbacks)"
kubectl exec -n "$NAMESPACE" gitlab-0 -- gitlab-rails runner \
  'ApplicationSetting.reset_column_information; key = OpenSSL::PKey::RSA.new(2048).to_pem; s = ApplicationSetting.new; s.ci_jwt_signing_key = key; s.ci_job_token_signing_key = key; ApplicationSetting.where(id: 1).update_all(encrypted_ci_jwt_signing_key: s.encrypted_ci_jwt_signing_key, encrypted_ci_jwt_signing_key_iv: s.encrypted_ci_jwt_signing_key_iv, encrypted_ci_job_token_signing_key: s.encrypted_ci_job_token_signing_key, encrypted_ci_job_token_signing_key_iv: s.encrypted_ci_job_token_signing_key_iv, updated_at: Time.current); s2 = ApplicationSetting.first; puts "jwt=#{s2.ci_jwt_signing_key.present?} job=#{s2.ci_job_token_signing_key.present?}"'

echo "==> Reload GitLab workers"
kubectl exec -n "$NAMESPACE" gitlab-0 -- gitlab-ctl hup puma
kubectl exec -n "$NAMESPACE" gitlab-0 -- gitlab-ctl hup sidekiq

echo "==> Done. Retry failed pipelines from GitLab UI or API."
