#!/usr/bin/env bash
# Rotate the agentic-book deploy PAT on blackpearl.
# Usage:  bash scripts/rotate-agentic-book-pat.sh <NEW_PAT>
#
# Updates every place the agentic-book deploy PAT is used:
#   1. ~/staging/secrets/agentic-book.env   (GHCR_TOKEN=)
#   2. ~/staging/secrets/ghcr-token         (bare token file)
#   3. ~/staging/agentic-book git origin URL (token-embedded)
#   4. k8s secret ghcr-regcred  (ns agentic-book)
# Revoking the old PAT on GitHub first is your step (Settings -> Developer
# settings -> Personal access tokens -> Revoke). Run THIS after minting the new one.
set -euo pipefail

NEW_PAT="${1:-}"
if [ -z "${NEW_PAT}" ]; then
  echo "usage: bash $(basename "$0") <NEW_PAT>" >&2
  exit 1
fi
if ! [[ "${NEW_PAT}" =~ ^(ghp_|gho_|ghu_|ghs_|github_pat_) ]]; then
  echo ">> warn: token does not start with a standard PAT prefix (ghp_/github_pat_/...)" >&2
fi

ENV_F="${HOME}/staging/secrets/agentic-book.env"
GT="${HOME}/staging/secrets/ghcr-token"
AG_REPO="${HOME}/staging/agentic-book"
NS="agentic-book"

echo ">> validating new token against api.github.com ..."
CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token ${NEW_PAT}" https://api.github.com/user)
if [ "${CODE}" != "200" ]; then
  echo ">> token failed validation (HTTP ${CODE}) - aborting, nothing changed." >&2
  exit 1
fi
GH_USER=$(curl -s -H "Authorization: token ${NEW_PAT}" https://api.github.com/user | sed -n 's/.*"login":[[:space:]]*"\([^"]*\)".*/\1/p')
echo ">> token valid (owner="${GH_USER:-unknown}")"

# GHCR docker username: keep the account that owns the package (from env), else token owner
DUSER=$(sed -nE 's/^GHCR_USERNAME=//p' "${ENV_F}" 2>/dev/null || true)
[ -n "${DUSER}" ] || DUSER="${GH_USER}"
DEMAIL=$(sed -nE 's/^GHCR_EMAIL=//p' "${ENV_F}" 2>/dev/null || true)
[ -n "${DEMAIL}" ] || DEMAIL="${DUSER}@users.noreply.github.com"

BK=$(date +%Y%m%d%H%M%S)

echo ">> 1/4 env file (backup ${ENV_F}.bak.${BK})"
cp "${ENV_F}" "${ENV_F}.bak.${BK}"
sed -i.bak "s#^GHCR_TOKEN=.*#GHCR_TOKEN=${NEW_PAT}#" "${ENV_F}"; rm -f "${ENV_F}.bak"

echo ">> 2/4 ghcr-token file (backup ${GT}.bak.${BK})"
cp "${GT}" "${GT}.bak.${BK}"
printf '%s' "${NEW_PAT}" > "${GT}"

echo ">> 3/4 agentic-book git origin"
( cd "${AG_REPO}" && git remote set-url origin "https://x-access-token:${NEW_PAT}@github.com/agentic-book-org/agentic-book.git" \
    && git ls-remote origin -h main >/dev/null 2>&1 && echo "   remote reachable with new token" )

echo ">> 4/4 k8s secret ${NS}/ghcr-regcred"
kubectl -n "${NS}" delete secret ghcr-regcred --ignore-not-found=true
kubectl -n "${NS}" create secret docker-registry ghcr-regcred \
  --docker-server=ghcr.io \
  --docker-username="${DUSER}" \
  --docker-password="${NEW_PAT}" \
  --docker-email="${DEMAIL}"

echo ">> done. Current rolled image:"
kubectl -n "${NS}" get deploy agentic-app -o jsonpath="{.spec.template.spec.containers[0].image}{\"\n\"}"
echo ">> Next: trigger CI (or push) to re-verify the private pull end-to-end."
