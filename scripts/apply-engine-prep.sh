#!/usr/bin/env bash
# Engine GPU node prep — SSH keys, NOPASSWD sudo, no password auth.
# Run on engine: sudo bash apply-engine-prep.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOSTNAME=engine
export STAGING_USER=s4il0r
bash "${SCRIPT_DIR}/apply-server-prep.sh" || true
# disable-sleep optional if present
[[ -x "${SCRIPT_DIR}/disable-sleep.sh" ]] && bash "${SCRIPT_DIR}/disable-sleep.sh"
# Drop Raspberry Pi headless defaults (password auth)
if [[ -f /etc/ssh/sshd_config.d/99-headless.conf ]]; then
  mv /etc/ssh/sshd_config.d/99-headless.conf /etc/ssh/sshd_config.d/99-headless.conf.bak
  sshd -t && systemctl reload ssh
fi
echo "engine prep done — test: ssh -i blackpearl root@engine id"
