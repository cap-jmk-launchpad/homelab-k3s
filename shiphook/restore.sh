#!/usr/bin/env bash
# Restore shiphook gateway config + restart service. Safe to re-run.
set -euo pipefail
LIVE=/home/s4il0r/staging/shiphook-server
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "[restore] latest backup:"
latest=$(ls -t /home/s4il0r/backups/shiphook-*.tar.gz 2>/dev/null | head -1 || true)
if [[ -n "$latest" ]]; then
  echo "[restore] restoring tarball $latest"
  sudo tar -xzf "$latest" -C /home/s4il0r/staging
elif [[ -f "$REPO_DIR/shiphook.yaml" ]]; then
  echo "[restore] restoring from git-tracked $REPO_DIR/shiphook.yaml"
  sudo cp "$REPO_DIR/shiphook.yaml" "$LIVE/shiphook.yaml"
else
  echo "[restore] ERROR no backup tarball AND no repo config" >&2; exit 1
fi
sudo test -s "$LIVE/.shiphook.staging.secret" || { echo "[restore] WARNING secret missing" >&2; }
sudo systemctl restart shiphook-staging.service
sleep 1
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Host: hook.obsevia.d3bu7.com" http://127.0.0.1:8080/deploy/staging/qroma)
echo "[restore] edge probe qroma -> $code (expect 401)"
test "$code" = "401" && echo "[restore] OK" || { echo "[restore] DEGRADED" >&2; exit 2; }
