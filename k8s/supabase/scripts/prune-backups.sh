#!/bin/sh
set -eu
RETENTION_DAYS="${RETENTION_DAYS:-30}"
find /backups -mindepth 1 -maxdepth 1 -type d -mtime +"${RETENTION_DAYS}" -print -exec rm -rf {} +
