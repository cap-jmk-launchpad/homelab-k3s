#!/usr/bin/env bash
# Homelab Shiphook entrypoint: build demo image, import to k3s, apply staging manifests.
# Run on blackpearl (s4il0r) via Shiphook. Webhook JSON env may pass GH_TOKEN, SKIP_BUILD, etc.
set -euo pipefail

DEMO="${OBSEVIA_DEMO:-${1:-}}"
[[ -n "$DEMO" ]] || { echo "usage: obsevia-shiphook-deploy.sh <qroma|ducah|dp>" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/load-env.sh
source "$ROOT/scripts/lib/load-env.sh" "$ROOT"

STAGING_USER="${STAGING_USER:-s4il0r}"
IMPORT_HOST="${IMPORT_HOST:-engine}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
OBSEVIA_DEMOS="${OBSEVIA_DEMOS_ROOT:-$HOME/staging/obsevia-demos}"
GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

clone_or_pull() {
  local repo="$1" dest="$2" branch="${3:-main}"
  local remote="https://github.com/obsevia-compliance/${repo}.git"
  if [[ -n "$GH_TOKEN" ]]; then
    remote="https://x-access-token:${GH_TOKEN}@github.com/obsevia-compliance/${repo}.git"
  fi
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" remote set-url origin "$remote"
    git -C "$dest" fetch --all --prune
    git -C "$dest" checkout "$branch"
    git -C "$dest" pull --ff-only origin "$branch" || true
    git -C "$dest" remote set-url origin "https://github.com/obsevia-compliance/${repo}.git"
  else
    mkdir -p "$(dirname "$dest")"
    git clone --branch "$branch" --depth 1 "$remote" "$dest"
    git -C "$dest" remote set-url origin "https://github.com/obsevia-compliance/${repo}.git"
  fi
}

import_image() {
  local tar="$1" image="$2"
  scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$tar" "${STAGING_USER}@${IMPORT_HOST}:/tmp/$(basename "$tar")"
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${STAGING_USER}@${IMPORT_HOST}" \
    "sudo k3s ctr images import /tmp/$(basename "$tar") && \
     sudo k3s ctr images tag localhost/${image} docker.io/library/${image} 2>/dev/null || true && \
     rm -f /tmp/$(basename "$tar")"
  rm -f "$tar"
}

load_supabase_from() {
  local envfile="$1"
  [[ -f "$envfile" ]] || return 0
  # shellcheck disable=SC1090
  set -a; source "$envfile"; set +a
}

case "$DEMO" in
  qroma)
    DEMO_DIR="${OBSEVIA_DEMOS}/QROMA-DEMO"
    clone_or_pull "QROMA-DEMO" "$DEMO_DIR" "master"
    load_supabase_from "$HOME/staging/secrets/obsevia.env"
    SUPABASE_URL="${NEXT_PUBLIC_SUPABASE_URL:-https://supabase.obsevia.com}"
    SUPABASE_ANON="${NEXT_PUBLIC_SUPABASE_ANON_KEY:-changeme-anon-key}"
    IMAGE="obsevia-qroma-demo-staging:latest"
    if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
      cd "$DEMO_DIR"
      command -v bun >/dev/null && bun run build || npm run build
      docker build -t "$IMAGE" \
        --build-arg "NEXT_PUBLIC_SUPABASE_URL=${SUPABASE_URL}" \
        --build-arg "NEXT_PUBLIC_SUPABASE_ANON_KEY=${SUPABASE_ANON}" \
        --build-arg "NEXT_PUBLIC_APP_URL=https://qroma.obsevia.com" \
        -f Dockerfile .
      docker tag "$IMAGE" "docker.io/library/${IMAGE}"
    fi
    if [[ "${SKIP_IMAGE_IMPORT:-0}" != 1 ]]; then
      TAR="$(mktemp /tmp/qroma-staging.XXXXXX.tar)"
      docker save -o "$TAR" "docker.io/library/${IMAGE}"
      import_image "$TAR" "$IMAGE"
    fi
    [[ -f "$ROOT/k8s/staging/qroma-demo/secret.yaml" ]] || cp "$ROOT/k8s/staging/qroma-demo/secret.example.yaml" "$ROOT/k8s/staging/qroma-demo/secret.yaml"
    export KUBECONFIG
    kubectl apply -f "$ROOT/k8s/staging/qroma-demo/secret.yaml"
    kubectl apply -k "$ROOT/k8s/staging/qroma-demo/base"
    kubectl -n obsevia-qroma-staging rollout status deployment/obsevia-qroma-demo --timeout=180s
    echo "[done] qroma staging → http://qroma.homelab.lan http://192.168.10.33:30584"
    ;;
  ducah)
    DEMO_DIR="${OBSEVIA_DEMOS}/DUCAH"
    clone_or_pull "DUCAH" "$DEMO_DIR" "main"
    load_supabase_from "$HOME/staging/secrets/obsevia.env"
    SUPABASE_URL="${NEXT_PUBLIC_SUPABASE_URL:-http://ducah.homelab.lan}"
    SUPABASE_ANON="${NEXT_PUBLIC_SUPABASE_ANON_KEY:-changeme-anon-key}"
    SUPABASE_UPSTREAM="${SUPABASE_UPSTREAM_URL:-http://192.168.10.41:30000}"
    IMAGE="obsevia-duca-demo-staging:latest"
    if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
      cd "$DEMO_DIR"
      podman build -t "$IMAGE" \
        --build-arg "NEXT_PUBLIC_SUPABASE_URL=${SUPABASE_URL}" \
        --build-arg "NEXT_PUBLIC_SUPABASE_ANON_KEY=${SUPABASE_ANON}" \
        --build-arg "SUPABASE_UPSTREAM_URL=${SUPABASE_UPSTREAM}" \
        -f Dockerfile .
      podman tag "$IMAGE" "docker.io/library/${IMAGE}"
    fi
    if [[ "${SKIP_IMAGE_IMPORT:-0}" != 1 ]]; then
      TAR="$(mktemp /tmp/ducah-staging.XXXXXX.tar)"
      podman save -o "$TAR" "docker.io/library/${IMAGE}"
      import_image "$TAR" "$IMAGE"
    fi
    [[ -f "$ROOT/k8s/staging/duca-demo/secret.yaml" ]] || cp "$ROOT/k8s/staging/duca-demo/secret.example.yaml" "$ROOT/k8s/staging/duca-demo/secret.yaml"
    export KUBECONFIG
    kubectl apply -f "$ROOT/k8s/staging/duca-demo/secret.yaml"
    kubectl apply -k "$ROOT/k8s/staging/duca-demo/overlays/engine"
    kubectl -n obsevia-ducah-staging rollout status deployment/obsevia-duca-demo --timeout=180s
    echo "[done] ducah staging → http://ducah.homelab.lan http://192.168.10.33:30583"
    ;;
  dp)
    DEMO_DIR="${OBSEVIA_DEMOS}/DP-DEMO"
    clone_or_pull "DP-DEMO" "$DEMO_DIR" "main"
    IMAGE="dp-demo:latest"
    if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
      cd "$DEMO_DIR"
      podman build -t "$IMAGE" \
        --build-arg "NEXT_PUBLIC_SITE_URL=https://dp.obsevia.com" \
        --build-arg "NEXT_PUBLIC_DEPLOY_ENV=staging" \
        -f Dockerfile .
      podman tag "$IMAGE" "docker.io/library/${IMAGE}"
    fi
    if [[ "${SKIP_IMAGE_IMPORT:-0}" != 1 ]]; then
      TAR="$(mktemp /tmp/dp-staging.XXXXXX.tar)"
      podman save -o "$TAR" "docker.io/library/${IMAGE}"
      for host in engine 192.168.10.41; do
        scp -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$TAR" "${STAGING_USER}@${host}:/tmp/dp-demo.tar"
        ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${STAGING_USER}@${host}" \
          "sudo k3s ctr images import /tmp/dp-demo.tar && \
           sudo k3s ctr images tag localhost/${IMAGE} docker.io/library/${IMAGE} 2>/dev/null || true && \
           rm -f /tmp/dp-demo.tar"
      done
      rm -f "$TAR"
    fi
    export KUBECONFIG
    kubectl apply -k "$DEMO_DIR/k8s"
    kubectl -n dp-demo rollout restart deployment/dp-demo
    kubectl -n dp-demo rollout status deployment/dp-demo --timeout=180s
    echo "[done] dp staging → http://dp.homelab.lan http://192.168.10.33:30582"
    ;;
  *)
    echo "unknown demo: $DEMO (expected qroma|ducah|dp)" >&2
    exit 1
    ;;
esac
