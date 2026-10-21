#!/usr/bin/env bash
# Apply GitLab + engine disk/image hygiene CronJobs (engine node).
# GitLab backup jobs (hourly/daily/secrets) remain in li-langverse/lis deploy/k8s/gitlab/ha/backup/.
#
# Usage:
#   export KUBECONFIG=$HOME/.kube/config-homelab
#   ./scripts/setup-engine-cron-hygiene.sh
#   ./scripts/setup-engine-cron-hygiene.sh --dry-run
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="${KUBECTL:-kubectl}"
DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    -h|--help)
      echo "usage: $0 [--dry-run]"
      exit 0
      ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

apply() {
  if [[ "$DRY" -eq 1 ]]; then
    echo "would apply: $*"
  else
    "$K" apply -f "$@"
  fi
}

echo "==> GitLab backup RBAC + prune + runner pod cleanup"
apply "$ROOT/k8s/gitlab/gitlab-backup-rbac.yaml"
apply "$ROOT/k8s/gitlab/gitlab-backup-prune-cronjob.yaml"
apply "$ROOT/k8s/gitlab/gitlab-runner-pod-cleanup-cronjob.yaml"

echo "==> Engine disk maintenance (6h): PVs, stale pods, crictl image prune on engine"
apply "$ROOT/k8s/engine-hygiene/rbac-engine-disk-maintenance.yaml"
apply "$ROOT/k8s/engine-hygiene/cronjob-engine-disk-maintenance.yaml"
apply "$ROOT/k8s/engine-hygiene/cronjob-engine-worker-disk-cleanup.yaml"

if [[ "$DRY" -eq 1 ]]; then
  echo "would: patch cronjob/engine-disk-maintenance suspend=false"
  echo "would: patch cronjob/engine-worker-disk-cleanup suspend=true"
  exit 0
fi

"$K" patch cronjob engine-disk-maintenance -n li-swarm \
  --type=merge -p '{"spec":{"suspend":false}}'
"$K" patch cronjob engine-worker-disk-cleanup -n li-swarm \
  --type=merge -p '{"spec":{"suspend":true}}' 2>/dev/null || true

echo ""
echo "==> CronJob status"
"$K" get cronjob -n gitlab gitlab-backup-prune gitlab-runner-pod-cleanup 2>/dev/null || true
"$K" get cronjob -n li-swarm engine-disk-maintenance engine-worker-disk-cleanup 2>/dev/null || true
echo ""
echo "Manual engine maintenance: bash scripts/engine-gitlab-backup-prune.sh"
echo "Trigger engine-disk-maintenance once:"
echo "  $K -n li-swarm create job --from=cronjob/engine-disk-maintenance engine-disk-maintenance-manual-\$(date -u +%Y%m%d%H%M%S)"
