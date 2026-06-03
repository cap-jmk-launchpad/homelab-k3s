#!/usr/bin/env bash
set -euo pipefail
if command -v vault >/dev/null; then vault version; exit 0; fi
[[ "$(uname -s)" == Linux ]] || { echo "ERROR: install vault CLI on this host" >&2; exit 1; }
sudo apt-get update -qq
sudo apt-get install -y -qq gnupg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
sudo apt-get update -qq && sudo apt-get install -y -qq vault
vault version
