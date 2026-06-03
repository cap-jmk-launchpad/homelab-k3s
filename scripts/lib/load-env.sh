#!/usr/bin/env bash
# Source repo-root .env (KEY=value lines). Safe to call when .env is missing.
load_repo_env() {
  local root="${1:-}"
  if [[ -z "$root" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
  local env_file=""
  if [[ -n "${LAUNCHPAD_ENV:-}" && -f "${LAUNCHPAD_ENV}" ]]; then
    env_file="${LAUNCHPAD_ENV}"
  elif [[ -f "$root/.env" ]]; then
    env_file="$root/.env"
  elif [[ -f "${HOME}/launchpad/.env" ]]; then
    env_file="${HOME}/launchpad/.env"
  fi
  [[ -n "$env_file" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  sed '1s/^\xEF\xBB\xBF//; s/\r$//' "$env_file" >"$tmp"
  set -a
  # shellcheck disable=SC1090
  source "$tmp"
  set +a
  rm -f "$tmp"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  load_repo_env "${1:-}"
fi
