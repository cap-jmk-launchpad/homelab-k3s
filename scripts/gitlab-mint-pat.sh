#!/usr/bin/env bash
# Mint a GitLab PAT via gitlab-rails on gitlab-0 (fastest API token path).
# Does not commit secrets — writes gitignored .gitlab-token.local by default.
#
# Usage:
#   ./scripts/gitlab-mint-pat.sh
#   PAT_NAME=dev-workstation PAT_SCOPES=api,read_api,read_repository,write_repository ./scripts/gitlab-mint-pat.sh
#   OUT_FILE=../.env.local ./scripts/gitlab-mint-pat.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/config-homelab}"
GITLAB_NAMESPACE="${GITLAB_NAMESPACE:-gitlab}"
GITLAB_POD="${GITLAB_POD:-gitlab-0}"
PAT_NAME="${PAT_NAME:-dev-workstation}"
PAT_SCOPES="${PAT_SCOPES:-api,read_api,read_repository,write_repository}"
OUT_FILE="${OUT_FILE:-${ROOT}/.gitlab-token.local}"
PAT_OUT_POD="/tmp/gitlab-mint-pat-out"
RAILS_SCRIPT_POD="/tmp/gitlab-mint-pat.rb"

export KUBECONFIG

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing $1" >&2
    exit 1
  }
}

require_cmd kubectl

cat <<'RUBY' | kubectl exec -i -n "$GITLAB_NAMESPACE" "$GITLAB_POD" -- tee "$RAILS_SCRIPT_POD" >/dev/null
user = User.find_by(username: "root") || User.admins.first
abort("no admin user") unless user

name = ENV.fetch("PAT_NAME")
scopes = ENV.fetch("PAT_SCOPES", "api,read_api,read_repository,write_repository").split(",").map(&:strip)
available = Gitlab::Auth.all_available_scopes.map(&:to_s)
scopes = scopes & available
abort("no valid scopes") if scopes.empty?

out_file = ENV.fetch("PAT_OUT_FILE", "/tmp/gitlab-mint-pat-out")

user.personal_access_tokens.where(name: name).find_each { |t| t.revoke! unless t.revoked? }

token = PersonalAccessToken.new(user: user, name: name, scopes: scopes, expires_at: 1.year.from_now)
token.save!
File.write(out_file, token.token)
$stderr.puts "minted name=#{name} scopes=#{scopes.join(',')} suffix=#{token.token[-4..]}"
RUBY

kubectl exec -n "$GITLAB_NAMESPACE" "$GITLAB_POD" -- env \
  PAT_NAME="$PAT_NAME" \
  PAT_SCOPES="$PAT_SCOPES" \
  PAT_OUT_FILE="$PAT_OUT_POD" \
  gitlab-rails runner "load '${RAILS_SCRIPT_POD}'"

token="$(kubectl exec -n "$GITLAB_NAMESPACE" "$GITLAB_POD" -- cat "$PAT_OUT_POD" | tr -d '\r')"
kubectl exec -n "$GITLAB_NAMESPACE" "$GITLAB_POD" -- rm -f "$PAT_OUT_POD" "$RAILS_SCRIPT_POD" >/dev/null 2>&1 || true

[[ -n "$token" ]] || { echo "ERROR: empty token from rails runner" >&2; exit 1; }

mkdir -p "$(dirname "$OUT_FILE")"
if [[ "$OUT_FILE" == *".env.local" ]] || [[ "$OUT_FILE" == *".env" ]]; then
  tmp="$(mktemp)"
  touch "$OUT_FILE"
  awk -v tok="$token" '
    BEGIN { done = 0 }
    /^GITLAB_TOKEN=/ { print "GITLAB_TOKEN=" tok; done = 1; next }
    { print }
    END { if (!done) print "GITLAB_TOKEN=" tok }
  ' "$OUT_FILE" >"$tmp"
  mv "$tmp" "$OUT_FILE"
else
  printf 'GITLAB_TOKEN=%s\n' "$token" >"$OUT_FILE"
  chmod 600 "$OUT_FILE" 2>/dev/null || true
fi

suffix="${token: -4}"
echo "OK: minted PAT name=${PAT_NAME} → ${OUT_FILE} (suffix …${suffix})"
