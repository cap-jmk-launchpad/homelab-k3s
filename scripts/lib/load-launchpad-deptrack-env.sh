#!/usr/bin/env bash
# Load only DEPTRACK_* keys from launchpad .env (avoids Windows paths breaking bash source).
load_launchpad_deptrack_env() {
  local env_file="${LAUNCHPAD_ENV:-}"
  [[ -n "$env_file" && -f "$env_file" ]] || return 0
  local tmp line key val
  tmp="$(mktemp)"
  sed '1s/^\xEF\xBB\xBF//; s/\r$//' "$env_file" >"$tmp"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^(DEPTRACK_[A-Za-z0-9_]+)=(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"
    val="${BASH_REMATCH[2]}"
    val="${val%\"}"
    val="${val#\"}"
    val="${val%\'}"
    val="${val#\'}"
    export "$key=$val"
  done <"$tmp"
  rm -f "$tmp"
}
