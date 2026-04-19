#!/bin/bash
# Set up a docker buildx builder that combines a native AMD64 node
# (running on an Intel Mac over SSH) with a native ARM64 node (local
# Apple Silicon). Avoids qemu emulation for amd64, which is slow and
# occasionally corrupts heavy Swift builds.
#
# Prerequisites:
#   - SSH access to the Intel Mac with Docker installed
#   - SSH key-based auth configured (test: ssh HOST docker version)
#
# Usage:
#   ./scripts/setup-remote-builder.sh HOST
#
# Example (Llamagraphics setup):
#   ./scripts/setup-remote-builder.sh samalone@ravana.local
#
# Run once per workstation. The builder is reused by
# scripts/build-production-image.sh on every release.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 SSH_HOST" >&2
    echo "Example: $0 samalone@ravana.local" >&2
    exit 1
fi

REMOTE_HOST="$1"
BUILDER_NAME="prospero-multi-arch"

echo "Testing SSH connection to $REMOTE_HOST..."
if ! ssh -o ConnectTimeout=5 "$REMOTE_HOST" "docker version" > /dev/null 2>&1; then
    echo "Error: Cannot reach Docker on $REMOTE_HOST." >&2
    echo "Check:" >&2
    echo "  - ssh $REMOTE_HOST works without a password (key auth)" >&2
    echo "  - Docker is running on the remote host" >&2
    echo "  - The remote user has Docker permissions (docker ps)" >&2
    exit 1
fi
echo "  ok"

if docker buildx inspect "$BUILDER_NAME" &> /dev/null; then
    echo "Removing existing builder '$BUILDER_NAME'..."
    docker buildx rm "$BUILDER_NAME"
fi

echo "Creating builder '$BUILDER_NAME'..."
echo "  amd64-node → $REMOTE_HOST (native)"
echo "  arm64-node → local (native)"

docker buildx create \
    --name "$BUILDER_NAME" \
    --driver docker-container \
    --platform linux/amd64 \
    --node amd64-node \
    "ssh://$REMOTE_HOST"

docker buildx create \
    --name "$BUILDER_NAME" \
    --append \
    --driver docker-container \
    --platform linux/arm64 \
    --node arm64-node

echo "Bootstrapping (downloads buildkit images, takes a moment)..."
docker buildx inspect --bootstrap "$BUILDER_NAME" > /dev/null

echo ""
echo "Done. Use with:"
echo "  docker buildx use $BUILDER_NAME"
echo ""
echo "Or just run ./scripts/release.sh — it'll pick up '$BUILDER_NAME' automatically."
echo ""
docker buildx ls | grep -E "^NAME|$BUILDER_NAME"
