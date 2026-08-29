#!/usr/bin/env bash
# Shiphook runScript for agentic-book-web (M1: CI builds, server rolls).
#
# Triggered by web-deploy.yml via the `agentic-book` Shiphook app route on blackpearl.
# Shiphook runs `git pull` in $SHIPHOOK_REPO_PATH (an agentic-book checkout) BEFORE
# this script, so HEAD == the commit CI just built+pushed. We read that SHA, target
# the GHCR image CI pushed, and roll the k3s Deployment.
#
# - No registry creds needed (GHCR package is public).
# - No Supabase keys needed at roll time (baked into the image at CI build time).
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
NS="${AGENTIC_BOOK_NS:-agentic-book-supabase}"
DEPLOY="${AGENTIC_BOOK_DEPLOY:-agentic-book-web}"
REPO_PATH="${SHIPHOOK_REPO_PATH:-$(pwd)}"
REGISTRY="${AGENTIC_BOOK_REGISTRY:-ghcr.io/agentic-book-org}"
IMAGE_NAME="${AGENTIC_BOOK_IMAGE_NAME:-agentic-book-web}"

SHA="$(git -C "$REPO_PATH" rev-parse --short=8 HEAD 2>/dev/null || echo "${AGENTIC_BOOK_TAG:-latest}")"
IMAGE="${REGISTRY}/${IMAGE_NAME}:main-${SHA}"

echo ">> [start] agentic-book-web deploy"
echo "   repo HEAD : ${SHA}"
echo "   image     : ${IMAGE}"
echo "   namespace : ${NS}"

# The Service (NodePort 30608) is applied once, out of band:
#   kubectl apply -f k8s/agentic-book/agentic-book-web.yaml
# It is NOT re-applied here to keep this script focused and path-independent.
kubectl -n "$NS" set image "deployment/${DEPLOY}" "${DEPLOY}=${IMAGE}"
kubectl -n "$NS" rollout status "deployment/${DEPLOY}" --timeout=180s

echo "[done] ok=true agentic-book-web ${IMAGE}"
