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

# Pick a builder — prefer a named multi-arch builder if one exists.
BUILDER="prospero-multi-arch"
if docker buildx inspect "$BUILDER" &> /dev/null; then
    echo "Using buildx builder '$BUILDER'"
    docker buildx use "$BUILDER"
elif docker buildx inspect multiplatform &> /dev/null; then
    echo "Using buildx builder 'multiplatform'"
    docker buildx use multiplatform
else
    echo "Creating buildx builder 'multiplatform'..."
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
