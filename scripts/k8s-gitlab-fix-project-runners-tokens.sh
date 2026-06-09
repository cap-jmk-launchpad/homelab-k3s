#!/usr/bin/env bash
# Clear corrupted projects.runners_token_encrypted after gitlab-secrets.json rotation.
# Symptom: trace PATCH 500 / OpenSSL::Cipher::CipherError in hide_secrets when appending
# job logs (runner shows "Appending trace to coordinator... error" despite healthy signing keys).
set -euo pipefail

NAMESPACE="${GITLAB_NAMESPACE:-gitlab}"
REGENERATE_ALL="${GITLAB_RUNNERS_TOKEN_REGENERATE_ALL:-1}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1" >&2; exit 1; }; }
require_cmd kubectl

echo "==> Clear corrupted project runners_token encryption columns"
cleared="$(kubectl exec -n "$NAMESPACE" gitlab-0 -- gitlab-psql -d gitlabhq_production -t -A -c \
  "UPDATE projects SET runners_token = NULL, runners_token_encrypted = NULL WHERE runners_token_encrypted IS NOT NULL; SELECT COUNT(*) FROM projects WHERE runners_token_encrypted IS NULL AND runners_token IS NULL;")"
echo "    projects with NULL runners_token after clear: ${cleared}"

echo "==> Regenerate project runners_token values"
if [[ "$REGENERATE_ALL" == "1" ]]; then
  kubectl exec -n "$NAMESPACE" gitlab-0 -- gitlab-rails runner \
    'fixed = 0; Project.find_each do |p|; begin; p.ensure_runners_token!; fixed += 1; rescue StandardError => e; puts "WARN #{p.full_path}: #{e.class}: #{e.message}"; end; end; puts "regenerated=#{fixed}"'
else
  kubectl exec -n "$NAMESPACE" gitlab-0 -- gitlab-rails runner \
    '%w[li-langverse/lic li-langverse/li-httpd li-langverse/li-cursor-agents].each do |path|; p = Project.find_by_full_path(path); next puts "skip missing #{path}" unless p; p.ensure_runners_token!; puts "regenerated #{path} len=#{p.runners_token.length}"; end'
fi

echo "==> Done. Retry failed pipelines from GitLab UI or API."
