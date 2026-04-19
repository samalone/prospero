#!/bin/bash
# Release a new version of Prospero.
#
# 1. Bump the version in k8s/overlays/prod/kustomization.yaml
# 2. Build and push the multi-platform production image
# 3. Apply manifests to the production cluster and wait for rollout
# 4. Commit the version change, tag it, and push
#
# Rolls back the version number if the Docker build fails.
#
# Usage: scripts/release.sh [major|minor|patch]

set -euo pipefail

BUMP="${1:-}"
case "$BUMP" in
    major|minor|patch) ;;
    *) echo "Usage: $0 [major|minor|patch]" >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: working directory has uncommitted changes." >&2
    git status --short >&2
    exit 1
fi
if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    echo "Error: working directory has untracked files." >&2
    git ls-files --others --exclude-standard >&2
    exit 1
fi

KUSTOMIZATION=k8s/overlays/prod/kustomization.yaml
ORIGINAL=$(yq '.images[] | select(.name == "llamagraphics/prospero") | .newTag' "$KUSTOMIZATION")

revert() {
    local code=$?
    if (( code != 0 )); then
        echo "==> Release failed (exit $code). Reverting version..." >&2
        yq -i "(.images[] | select(.name == \"llamagraphics/prospero\") | .newTag) = \"$ORIGINAL\"" "$KUSTOMIZATION"
        echo "==> Version reverted to $ORIGINAL" >&2
    fi
    exit "$code"
}
trap revert EXIT

# Tests run locally on native arm64 before we kick off the
# multi-platform production build, which skips them to avoid flaky qemu
# emulation. Fail fast if tests break.
echo "==> Running tests locally..."
if ! swift test; then
    echo "Error: tests failed. Aborting release." >&2
    exit 1
fi

echo "==> Bumping $BUMP version..."
./scripts/bump.sh "$BUMP"

VERSION=$(yq '.images[] | select(.name == "llamagraphics/prospero") | .newTag' "$KUSTOMIZATION")
echo "==> New version: $VERSION"

echo "==> Building production image..."
./scripts/build-production-image.sh

echo "==> Regenerating secrets (if needed)..."
if [[ ! -f k8s/overlays/prod/secrets.yaml ]]; then
    ./scripts/inject-secrets.sh prod
fi

echo "==> Applying manifests to production..."
kubectl --context pc apply -k k8s/overlays/prod

# Past this point we're live; don't revert the version on failure.
trap - EXIT

kubectl --context pc rollout restart deployment/prospero
kubectl --context pc rollout status deployment/prospero

echo "==> Committing $VERSION..."
git add "$KUSTOMIZATION"
git commit -m "Version $VERSION"
git tag -a "$VERSION" -m "Release $VERSION"
git push origin main
git push origin "$VERSION"

echo ""
echo "Released Prospero $VERSION."
