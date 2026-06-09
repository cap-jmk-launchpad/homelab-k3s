#!/usr/bin/env bash
set -euo pipefail
CSS="${1:-/assets/application-d9fbd7cb5325059aa5dd859be97da763569721107347c84973f86a22328889df.css}"
echo "CSS path: ${CSS}"
echo "AFTER-HTTPS-WAN:"
curl -sk "https://gitlab.lilangverse.xyz${CSS}" -o /tmp/css-wan-after.bin -w 'dl=%{size_download} ct=%{content_type}\n'
wc -c /tmp/css-wan-after.bin
curl -skI "https://gitlab.lilangverse.xyz${CSS}" | grep -i content || true
echo "AFTER-HTTPS-local443:"
curl -sk -H 'Host: gitlab.lilangverse.xyz' "https://127.0.0.1${CSS}" -o /tmp/css-local-after.bin -w 'dl=%{size_download} ct=%{content_type}\n'
wc -c /tmp/css-local-after.bin
curl -skI -H 'Host: gitlab.lilangverse.xyz' "https://127.0.0.1${CSS}" | grep -i content || true
echo "AFTER-HTTP-80:"
curl -s -H 'Host: gitlab.lilangverse.xyz' "http://127.0.0.1:80${CSS}" -o /tmp/css-http-after.bin -w 'dl=%{size_download} ct=%{content_type}\n'
wc -c /tmp/css-http-after.bin
curl -sI -H 'Host: gitlab.lilangverse.xyz' "http://127.0.0.1:80${CSS}" | grep -i content || true
