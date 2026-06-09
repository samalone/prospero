#!/bin/bash
# Build and push a multi-platform production image for Prospero.
#
# Platforms: linux/amd64 (Linode) and linux/arm64 (local M-series dev).
# Version tag comes from the `newTag` field in
# k8s/overlays/prod/kustomization.yaml, so the image tag always matches
# the deployed version.
#
# Prerequisites:
#   - docker buildx set up for multi-platform builds (native AMD64 via
#     the shared 'llama' builder is ideal; see
#     ~/maintenance/scripts/setup-llama-builder.sh)
#   - logged in to Docker Hub
#   - yq (brew install yq)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KUSTOMIZATION="$PROJECT_ROOT/k8s/overlays/prod/kustomization.yaml"

if ! command -v yq &> /dev/null; then
    echo "Error: yq not installed. brew install yq" >&2
    exit 1
fi

VERSION=$(yq eval '.images[0].newTag' "$KUSTOMIZATION")
if [[ -z "$VERSION" ]] || [[ "$VERSION" == "null" ]]; then
    echo "Error: could not read newTag from $KUSTOMIZATION" >&2
    exit 1
fi

IMAGE="llamagraphics/prospero"

echo "Building multi-platform image for Prospero v$VERSION..."

if ! docker buildx version &> /dev/null; then
    echo "Error: docker buildx not available" >&2
    exit 1
fi

# Prefer the shared multi-arch builder 'llama' if it exists — it has a
# native AMD64 node on the Intel Mac build server, created by
# ~/maintenance/scripts/setup-llama-builder.sh. Without it, buildx
# falls back to emulated amd64 (Rosetta 2 on Docker Desktop, qemu
# otherwise), which is slow and occasionally breaks heavy Swift
# compilations.
#
# Stop the remote builder on exit so SSH connections don't accumulate;
# the builder auto-starts on next use.
BUILDER="llama"
REMOTE_BUILDER=""
cleanup() {
    if [[ -n "$REMOTE_BUILDER" ]]; then
        docker buildx stop "$REMOTE_BUILDER" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if docker buildx inspect "$BUILDER" &> /dev/null; then
    echo "Using shared multi-arch builder '$BUILDER'"
    docker buildx use "$BUILDER"
    REMOTE_BUILDER="$BUILDER"
elif docker buildx inspect multiplatform &> /dev/null; then
    echo "WARNING: builder '$BUILDER' not found; using 'multiplatform' (emulated amd64)" >&2
    echo "         Run ~/maintenance/scripts/setup-llama-builder.sh for native builds." >&2
    docker buildx use multiplatform
else
    echo "WARNING: creating emulated builder 'multiplatform' — run ~/maintenance/scripts/setup-llama-builder.sh for native builds." >&2
    docker buildx create --name multiplatform --use
fi

docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --build-arg APP_VERSION="$VERSION" \
    --tag "$IMAGE:$VERSION" \
    --tag "$IMAGE:latest" \
    --push \
    "$PROJECT_ROOT"

echo ""
echo "Pushed:"
echo "  $IMAGE:$VERSION"
echo "  $IMAGE:latest"
