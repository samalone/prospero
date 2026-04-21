#!/bin/bash
# Bump the image tag in k8s/overlays/prod/kustomization.yaml.
#
# Usage: scripts/bump.sh [major|minor|patch]
#
# Requires: yq (brew install yq), semver CLI (npm i -g semver) — or
# we parse semver manually.

set -euo pipefail

BUMP="${1:-}"
case "$BUMP" in
    major|minor|patch) ;;
    *) echo "Usage: $0 [major|minor|patch]" >&2; exit 1 ;;
esac

cd "$(dirname "$0")/.."
KUSTOMIZATION=k8s/overlays/prod/kustomization.yaml

CURRENT=$(yq '.images[] | select(.name == "llamagraphics/prospero") | .newTag' "$KUSTOMIZATION")
if [[ -z "$CURRENT" ]] || [[ "$CURRENT" == "null" ]]; then
    echo "Error: could not read current version from $KUSTOMIZATION" >&2
    exit 1
fi

# Parse MAJOR.MINOR.PATCH.
if [[ ! "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: current version '$CURRENT' is not semver" >&2
    exit 1
fi
MAJOR=${BASH_REMATCH[1]}
MINOR=${BASH_REMATCH[2]}
PATCH=${BASH_REMATCH[3]}

case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
esac
NEW="$MAJOR.$MINOR.$PATCH"

yq -i "(.images[] | select(.name == \"llamagraphics/prospero\") | .newTag) = \"$NEW\"" \
    "$KUSTOMIZATION"

# Swift-side constant displayed in the app footer. Kept in sync with
# the kustomization image tag so the running app self-reports what's
# actually deployed.
VERSION_SWIFT=Sources/Prospero/Version.swift
sed -i '' -E "s/(let prosperoVersion = )\"[0-9]+\.[0-9]+\.[0-9]+\"/\1\"$NEW\"/" "$VERSION_SWIFT"

echo "$CURRENT -> $NEW"
