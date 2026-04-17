#!/bin/bash
# Build the Prospero Docker image and deploy to the docker-desktop
# Kubernetes cluster. Uses the `dev` overlay which mounts at root and
# points at the local life-balance Postgres pod.
#
# Verbose build output goes to logs/deploy-dev.log; only status and
# errors land on the console.

set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p logs
LOG=logs/deploy-dev.log

# APP_VERSION is used by the binary (version banner) and the browser
# (to bust the static-asset cache). Use a build timestamp for dev.
APP_VERSION="dev-$(date +%s)"

# Ensure dev secrets exist — generate from the template on first run.
if [[ ! -f k8s/overlays/dev/secrets.yaml ]]; then
    echo "k8s/overlays/dev/secrets.yaml not found. Generating from 1Password..."
    ./scripts/inject-secrets.sh dev
fi

echo "Building Docker image (log: $LOG)..."
if ! docker build \
    --build-arg APP_VERSION="$APP_VERSION" \
    -t llamagraphics/prospero:dev \
    . > "$LOG" 2>&1; then
    echo "ERROR: Docker build failed. Last 20 lines:" >&2
    tail -20 "$LOG" >&2
    exit 1
fi

echo "Applying Kubernetes manifests..."
kubectl --context docker-desktop apply -k k8s/overlays/dev >> "$LOG" 2>&1

echo "Restarting deployment..."
kubectl --context docker-desktop \
    rollout restart deployment/prospero >> "$LOG" 2>&1

echo "Waiting for rollout..."
if ! kubectl --context docker-desktop \
    rollout status deployment/prospero >> "$LOG" 2>&1; then
    echo "ERROR: Rollout failed. Last 20 lines:" >&2
    tail -20 "$LOG" >&2
    exit 1
fi

echo "Dev deployment complete."
