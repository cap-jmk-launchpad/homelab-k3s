#!/usr/bin/env bash
# Emergency admin password reset via Postgres (when UI/API password is unknown).
# Usage: NEW_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)" ./scripts/k8s-dependency-track-reset-admin-db.sh
set -euo pipefail

DEPTRACK_NAMESPACE="${DEPTRACK_NAMESPACE:-dependency-track}"
DEPTRACK_ADMIN_USER="${DEPTRACK_ADMIN_USER:-admin}"
new_pw="${NEW_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing $1" >&2
    exit 1
  }
}

require_cmd kubectl
require_cmd python3

pg_pass="$(kubectl -n "$DEPTRACK_NAMESPACE" get secret dependency-track-secrets -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"
hash="$(NEW_PASSWORD="$new_pw" python3 - <<'PY'
from hashlib import sha512
import bcrypt
import os
password = os.environ["NEW_PASSWORD"]
prehash = sha512(password.encode()).hexdigest().encode()
salt = bcrypt.gensalt(rounds=14, prefix=b"2a")
print(bcrypt.hashpw(prehash, salt).decode())
PY
)"

kubectl -n "$DEPTRACK_NAMESPACE" exec dependency-track-postgres-0 -- \
  env PGPASSWORD="$pg_pass" psql -U dtrack -d dtrack -v ON_ERROR_STOP=1 -c \
  "UPDATE \"MANAGEDUSER\" SET \"PASSWORD\" = '${hash}', \"FORCE_PASSWORD_CHANGE\" = false, \"LAST_PASSWORD_CHANGE\" = NOW() WHERE \"USERNAME\" = '${DEPTRACK_ADMIN_USER}';"

echo "==> reset ${DEPTRACK_ADMIN_USER} password in Postgres"
echo "    (export NEW_PASSWORD for bootstrap script to pick up)"
