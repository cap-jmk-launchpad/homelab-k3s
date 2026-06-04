#!/usr/bin/env bash
# Install HashiCorp vault + hcp CLIs (Debian/Ubuntu).
set -euo pipefail

install_hashicorp_apt() {
  local codename pkgs
  codename="$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-}")"
  [[ -n "$codename" ]] || codename="$(lsb_release -cs 2>/dev/null || true)"
  case "$codename" in
    trixie|forky) codename=bookworm ;;
  esac
  [[ -n "$codename" ]] || { echo "ERROR: cannot detect apt codename" >&2; exit 1; }
  sudo apt-get update -qq
  sudo apt-get install -y -qq gnupg curl ca-certificates
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${codename} main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -qq
  pkgs=()
  command -v vault >/dev/null || pkgs+=(vault)
  command -v hcp >/dev/null || pkgs+=(hcp)
  [[ ${#pkgs[@]} -eq 0 ]] || sudo apt-get install -y -qq "${pkgs[@]}"
}

[[ "$(uname -s)" == Linux ]] || { echo "ERROR: install vault/hcp CLI on this host" >&2; exit 1; }
if command -v vault >/dev/null && command -v hcp >/dev/null; then
  vault version
  hcp version
  exit 0
fi
install_hashicorp_apt
command -v vault >/dev/null && vault version
command -v hcp >/dev/null && hcp version
