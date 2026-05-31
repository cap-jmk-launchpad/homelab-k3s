#!/usr/bin/env bash
# Run training smoke tests on the homelab cluster.
# Usage: ./scripts/k8s-training-smoke.sh [gpu|ddp|sweep|cpu|all]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-gpu}"

wait_job() {
  local ns=$1 job=$2 timeout=${3:-600}
  echo "==> wait for job/${job}"
  kubectl -n "$ns" wait --for=condition=complete "job/${job}" --timeout="${timeout}s"
  kubectl -n "$ns" logs "job/${job}" --all-containers --prefix=true || true
}

run_gpu() {
  echo "==> single-GPU smoke (engine)"
  kubectl apply -f "$ROOT/k8s/training/gpu-smoke-job.yaml"
  wait_job training gpu-smoke 120
}

run_ddp() {
  echo "==> PyTorch DDP smoke (engine + desktop)"
  kubectl delete job pytorch-ddp-smoke -n training --ignore-not-found
  kubectl apply -f "$ROOT/k8s/training/pytorch-ddp-smoke.yaml"
  wait_job training pytorch-ddp-smoke 600
}

run_sweep() {
  echo "==> indexed parameter sweep"
  kubectl delete job param-sweep -n training --ignore-not-found
  kubectl apply -f "$ROOT/k8s/training/indexed-sweep-job.yaml"
  wait_job training param-sweep 300
}

run_cpu() {
  echo "==> CPU fanout on deck + anch0r"
  kubectl delete job cpu-fanout -n training --ignore-not-found
  kubectl apply -f "$ROOT/k8s/training/cpu-fanout-job.yaml"
  wait_job training cpu-fanout 300
}

case "$MODE" in
  gpu) run_gpu ;;
  ddp) run_ddp ;;
  sweep) run_sweep ;;
  cpu) run_cpu ;;
  all)
    run_gpu
    run_sweep
    run_cpu
    run_ddp
    ;;
  *)
    echo "Usage: $0 [gpu|ddp|sweep|cpu|all]" >&2
    exit 1
    ;;
esac

echo "==> done ($MODE)"
