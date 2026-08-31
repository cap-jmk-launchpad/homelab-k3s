#!/usr/bin/env bash
# Shiphook runScript for agentic-book-web (M1: CI builds, server rolls).
#
# CI (web-deploy.yml) built+pushed ghcr.io/agentic-book-org/agentic-book-web:main-<sha>
# to a (private) GHCR package, then POSTed an empty deploy trigger. Shiphook did
# `git pull` in $repoPath (an agentic-book checkout) before this script runs, so
# HEAD == the commit CI just deployed. We read that SHA (8 chars, matching CI's
# ${GITHUB_SHA::8} tag), create a GHCR imagePullSecret from a server-side PAT
# (private-package pull; never committed), patch the Deployment to use it, then
# roll. No cluster credential or PAT ever touches CI or git.
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
NS="${AGENTIC_BOOK_NS:-agentic-book}"
DEPLOY="${AGENTIC_BOOK_DEPLOY:-agentic-app}"
REPO_PATH="${SHIPHOOK_REPO_PATH:-$(pwd)}"
REGISTRY="${AGENTIC_BOOK_REGISTRY:-ghcr.io/agentic-book-org}"
IMAGE_NAME="${AGENTIC_BOOK_IMAGE_NAME:-agentic-book-web}"

# Server-side PAT for pulling the private GHCR package (operator-managed).
# File: ~/staging/secrets/agentic-book.env  -> GHCR_USERNAME, GHCR_TOKEN
# (see docs/agentic-book-cd.md). Override the path via AGENTIC_BOOK_SECRET_FILE.
ENV_FILE="${AGENTIC_BOOK_SECRET_FILE:-$HOME/staging/secrets/agentic-book.env}"
if [ -f "$ENV_FILE" ]; then set -a; . "$ENV_FILE"; set +a; fi

SHA="$(git -C "$REPO_PATH" rev-parse --short=8 HEAD 2>/dev/null || echo "${AGENTIC_BOOK_TAG:-latest}")"
IMAGE="${REGISTRY}/${IMAGE_NAME}:main-${SHA}"

echo ">> [start] agentic-book-web deploy"
echo "   repo HEAD : ${SHA}"
echo "   image     : ${IMAGE}"
echo "   namespace : ${NS}"

# imagePullSecret for the PRIVATE GHCR package (idempotent; base64 by kubectl).
if [ -n "${GHCR_USERNAME:-}" ] && [ -n "${GHCR_TOKEN:-}" ]; then
  kubectl -n "$NS" create secret docker-registry ghcr-regcred \
    --docker-server=ghcr.io \
    --docker-username="$GHCR_USERNAME" \
    --docker-password="$GHCR_TOKEN" \
    --docker-email="${GHCR_EMAIL:-deploy@agentic-book.org}" \
    --dry-run=client -o yaml | kubectl -n "$NS" apply -f -
else
  echo ">> warn: GHCR_USERNAME/GHCR_TOKEN unset — assuming public image or existing pull secret"
fi

kubectl -n "$NS" set image "deployment/${DEPLOY}" "app=${IMAGE}"
kubectl -n "$NS" rollout status "deployment/${DEPLOY}" --timeout=180s

echo "[done] ok=true agentic-book-web ${IMAGE}"
