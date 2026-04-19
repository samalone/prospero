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
#     a remote builder is ideal; see scripts/setup-remote-builder.sh
#     once we add one)
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

# Prefer the named multi-arch builder if it exists — it's the one with a
# native AMD64 node on the Intel Mac build server, created by
# scripts/setup-remote-builder.sh. Without it, buildx falls back to
# qemu emulation for amd64, which stalls and sometimes corrupts heavy
# Swift compilations.
#
# Stop the remote builder on exit so SSH connections don't accumulate;
# the builder auto-starts on next use.
BUILDER="prospero-multi-arch"
REMOTE_BUILDER=""
cleanup() {
    if [[ -n "$REMOTE_BUILDER" ]]; then
        docker buildx stop "$REMOTE_BUILDER" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if docker buildx inspect "$BUILDER" &> /dev/null; then
    echo "Using remote multi-arch builder '$BUILDER'"
    docker buildx use "$BUILDER"
    REMOTE_BUILDER="$BUILDER"
elif docker buildx inspect multiplatform &> /dev/null; then
    echo "Using buildx builder 'multiplatform' (qemu — run scripts/setup-remote-builder.sh for native)"
    docker buildx use multiplatform
else
    echo "Creating buildx builder 'multiplatform' (qemu — run scripts/setup-remote-builder.sh for native)..."
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
