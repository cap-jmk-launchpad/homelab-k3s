#!/bin/sh
set -eu
RETENTION_DAYS="${RETENTION_DAYS:-30}"
find /backups -maxdepth 1 -type f \( -name '*_gitlab_backup.tar' -o -name '*.README.txt' \) -mtime +"${RETENTION_DAYS}" -print -delete
