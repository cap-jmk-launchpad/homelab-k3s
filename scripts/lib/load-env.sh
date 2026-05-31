#!/usr/bin/env bash
# Source repo-root .env (KEY=value lines). Safe to call when .env is missing.
load_repo_env() {
  local root="${1:-}"
  if [[ -z "$root" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
  local env_file="$root/.env"
  [[ -f "$env_file" ]] || return 0
  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  load_repo_env "${1:-}"
fi
