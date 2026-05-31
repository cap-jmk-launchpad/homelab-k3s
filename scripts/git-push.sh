#!/usr/bin/env bash
# Push to GitHub using GH_TOKEN from repo-root .env (never commit .env).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh" "$ROOT"

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  echo "Set GH_TOKEN in ${ROOT}/.env (copy from .env.example)" >&2
  exit 1
fi

REMOTE="${1:-origin}"
LOCAL_BRANCH="${2:-$(git -C "$ROOT" branch --show-current)}"
UPSTREAM_BRANCH="${3:-main}"

cd "$ROOT"
GIT_TERMINAL_PROMPT=0 git \
  -c "http.extraHeader=Authorization: Bearer ${TOKEN}" \
  push "$REMOTE" "${LOCAL_BRANCH}:${UPSTREAM_BRANCH}"
