#!/usr/bin/env bash
# Push to GitHub using GH_TOKEN from repo-root .env (never commit .env).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh" "$ROOT"
load_repo_env "$ROOT"

TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [[ -z "$TOKEN" ]]; then
  echo "Set GH_TOKEN in ${ROOT}/.env (copy from .env.example)" >&2
  exit 1
fi

REMOTE="${1:-origin}"
LOCAL_BRANCH="${2:-$(git -C "$ROOT" branch --show-current)}"
UPSTREAM_BRANCH="${3:-main}"

cd "$ROOT"
ORIGIN_URL="$(git remote get-url "$REMOTE")"
case "$ORIGIN_URL" in
  https://github.com/*)
    REPO_PATH="${ORIGIN_URL#https://github.com/}"
    ;;
  git@github.com:*)
    REPO_PATH="${ORIGIN_URL#git@github.com:}"
    ;;
  *)
    echo "Unsupported remote URL: $ORIGIN_URL" >&2
    exit 1
    ;;
esac
REPO_PATH="${REPO_PATH%.git}"
PUSH_URL="https://x-access-token:${TOKEN}@github.com/${REPO_PATH}.git"

GIT_TERMINAL_PROMPT=0 git push "$PUSH_URL" "${LOCAL_BRANCH}:${UPSTREAM_BRANCH}"
