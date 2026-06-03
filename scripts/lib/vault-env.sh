#!/usr/bin/env bash
# Vault/HCP env helpers — preserve credentials across routine deploys.
#
# shellcheck source=load-env.sh

_vault_env_keys=(VAULT_ADDR VAULT_TOKEN VAULT_NAMESPACE HCP_CLIENT_ID HCP_CLIENT_SECRET)

load_vault_env() {
  local root="${1:-}"
  local key val line env_file
  local -A saved=()

  for key in "${_vault_env_keys[@]}"; do
    saved["$key"]="${!key-}"
  done

  # shellcheck source=load-env.sh
  source "$(dirname "${BASH_SOURCE[0]}")/load-env.sh"
  load_repo_env "$root"

  env_file=""
  if [[ -n "$root" && -f "$root/.env" ]]; then
    env_file="$root/.env"
  elif [[ -n "${LAUNCHPAD_ENV:-}" && -f "${LAUNCHPAD_ENV}" ]]; then
    env_file="${LAUNCHPAD_ENV}"
  elif [[ -f "${HOME}/launchpad/.env" ]]; then
    env_file="${HOME}/launchpad/.env"
  fi

  if [[ -n "$env_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [[ "$line" != *=* ]] && continue
      key="${line%%=*}"
      val="${line#*=}"
      val="${val%\"}"; val="${val#\"}"
      val="${val%\'}"; val="${val#\'}"
      case "$key" in
        VAULT_ADDR|VAULT_TOKEN|VAULT_NAMESPACE|HCP_CLIENT_ID|HCP_CLIENT_SECRET) ;;
        *) continue ;;
      esac
      [[ -n "$val" ]] && saved["$key"]="$val"
    done <"$env_file"
  fi

  if [[ "${VAULT_REGENERATE:-0}" != 1 && "${HCP_REGENERATE:-0}" != 1 ]]; then
    for key in "${_vault_env_keys[@]}"; do
      [[ -n "${saved[$key]:-}" ]] && export "$key=${saved[$key]}"
    done
  fi

  export VAULT_NAMESPACE="${VAULT_NAMESPACE:-admin}"
}

vault_env_upsert() {
  local env_file="$1"
  local key="$2"
  local val="$3"
  local force="${4:-0}"

  [[ -f "$env_file" ]] || touch "$env_file"
  if [[ "$force" != 1 && "${VAULT_REGENERATE:-0}" != 1 && "${HCP_REGENERATE:-0}" != 1 ]]; then
    if grep -qE "^${key}=" "$env_file" 2>/dev/null; then
      local existing
      existing="$(grep -E "^${key}=" "$env_file" | tail -1 | cut -d= -f2- | tr -d '\r' | sed 's/^["'\'']//;s/["'\'']$//')"
      [[ -n "$existing" ]] && return 1
    fi
  fi
  if grep -qE "^${key}=" "$env_file" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    grep -vE "^${key}=" "$env_file" >"$tmp" || true
    mv "$tmp" "$env_file"
  fi
  printf '%s=%s\n' "$key" "$val" >>"$env_file"
}
