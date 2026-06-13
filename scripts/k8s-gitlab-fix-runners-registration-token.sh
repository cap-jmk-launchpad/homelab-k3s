#!/usr/bin/env bash
# Restore instance runners_registration_token after k8s-gitlab-fix-ci-signing-keys.sh
# nulls runners_registration_token_encrypted (runner register POST /api/v4/runners -> 500).
set -eu

NAMESPACE="${GITLAB_NAMESPACE:-gitlab}"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing $1" >&2; exit 1; }; }
require_cmd kubectl

echo "==> Sync runners_registration_token from /etc/gitlab/gitlab.rb (update_all bypasses AR decrypt callbacks)"
kubectl exec -n "$NAMESPACE" gitlab-0 -- bash -c '
set -eu
TOKEN=$(grep initial_shared_runners_registration_token /etc/gitlab/gitlab.rb | sed -n "s/.*= *'\''\([^'\'']*\)'\''.*/\1/p")
test -n "$TOKEN"
export REG_TOKEN="$TOKEN"
gitlab-rails runner "
ApplicationSetting.reset_column_information
token = ENV.fetch(\"REG_TOKEN\")
draft = ApplicationSetting.new
draft.set_runners_registration_token(token)
enc = draft.read_attribute(:runners_registration_token_encrypted)
ApplicationSetting.where(id: 1).update_all(runners_registration_token_encrypted: enc, updated_at: Time.current)
s = ApplicationSetting.current
puts \"runners_registration_token_present=#{s.runners_registration_token.present?}\"
"
'

echo "==> Reload GitLab workers"
kubectl exec -n "$NAMESPACE" gitlab-0 -- gitlab-ctl hup puma
kubectl exec -n "$NAMESPACE" gitlab-0 -- gitlab-ctl hup sidekiq

echo "==> Restart gitlab-runner deployment"
kubectl -n "$NAMESPACE" rollout restart deployment/gitlab-runner
kubectl -n "$NAMESPACE" rollout status deployment/gitlab-runner --timeout=300s || true

echo "==> Done. If jobs still Pending with bad node selectors, run k8s-gitlab-runner-patch-config.sh"
