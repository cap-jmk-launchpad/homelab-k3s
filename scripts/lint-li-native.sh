#!/usr/bin/env bash
# Alias for homelab-edge-policy-check.sh (li-native edge policy).
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/homelab-edge-policy-check.sh" "$@"
