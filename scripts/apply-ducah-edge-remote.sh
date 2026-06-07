#!/usr/bin/env bash
set -euo pipefail
EDGE="${HOME}/staging/beelink-cleanup/k8s/edge"
MAJICO="${HOME}/staging/majico-deploy/deploy/staging/edge/majico-staging.httpd.toml"
RUNTIME="/run/li-httpd"
FLATTEN="${HOME}/staging/li-httpd/scripts/flatten-httpd-config.py"

sudo mkdir -p "$RUNTIME"
sudo python3 "$EDGE/merge-httpd-config.py" "$EDGE/homelab.httpd.toml" "$MAJICO" -o "$RUNTIME/homelab.httpd.toml" --validate
sudo python3 "$FLATTEN" "$RUNTIME/homelab.httpd.toml" -o "$RUNTIME/homelab.runtime.conf"
sudo systemctl restart li-httpd-homelab
sleep 2
curl -sS -o /dev/null -w 'edge:%{http_code}\n' -H 'Host: ducah.homelab.lan' http://127.0.0.1/login
curl -sS -o /dev/null -w 'nodeport:%{http_code}\n' http://127.0.0.1:30583/login
