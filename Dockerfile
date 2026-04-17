# Multi-stage Dockerfile for Prospero
# Stage 1: Build with Swift 6.2 on Ubuntu 24.04 (Noble)
# Stage 2: Slim runtime with just the binary and resource bundles
#
# Modeled on Life Balance's Dockerfile.

# ── Build stage ──────────────────────────────────────────────────────────────

FROM swift:6.2-noble AS builder

# TARGETARCH is automatically provided by BuildKit when using --platform.
# We use it for architecture-specific cache IDs so AMD64 and ARM64 builds
# don't step on each other's cache.
ARG TARGETARCH

# SKIP_TESTS can be "true" for multi-platform production builds where the
# test pass has already happened on the dev machine (tests aren't native
# to every platform we emit).
ARG SKIP_TESTS=false

# APP_VERSION is passed by scripts/build-production-image.sh from the
# newTag field in k8s/overlays/prod/kustomization.yaml, so the built
# binary is stamped with the version it ships as.
ARG APP_VERSION=dev

WORKDIR /app

# Resolve dependencies first — this layer only rebuilds when manifests change.
COPY Package.swift Package.resolved ./
RUN --mount=type=cache,target=/root/.swiftpm,id=prospero-swiftpm-${TARGETARCH} \
    --mount=type=cache,target=/app/.build,id=prospero-build-${TARGETARCH} \
    swift package resolve

# Copy sources and tests.
COPY Sources/ ./Sources/
COPY Tests/ ./Tests/

# Run tests in debug on the build platform only. All Prospero tests are
# hermetic (no external services) so this catches Linux-specific issues.
RUN --mount=type=cache,target=/root/.swiftpm,id=prospero-swiftpm-${TARGETARCH} \
    --mount=type=cache,target=/app/.build,id=prospero-build-${TARGETARCH} \
    if [ "$SKIP_TESTS" != "true" ]; then swift test; fi

# Release build with static stdlib linking. Binary + resource bundles are
# copied out of the cache mount into /tmp so they survive into the runtime
# stage (cache mounts are not part of the layer).
RUN --mount=type=cache,target=/root/.swiftpm,id=prospero-swiftpm-${TARGETARCH} \
    --mount=type=cache,target=/app/.build,id=prospero-build-${TARGETARCH} \
    swift build -c release --product Prospero -Xswiftc -static-stdlib && \
    RELEASE_DIR=$(find /app/.build -type d \( \
        -path "*/aarch64-unknown-linux-gnu/release" -o \
        -path "*/x86_64-unknown-linux-gnu/release" \
    \) 2>/dev/null | head -1) && \
    if [ -z "$RELEASE_DIR" ]; then \
        RELEASE_DIR=$(find /app/.build -type d -name "release" 2>/dev/null | head -1); \
    fi && \
    if [ -z "$RELEASE_DIR" ] || [ ! -f "$RELEASE_DIR/Prospero" ]; then \
        echo "ERROR: Release binary not found" && \
        find /app/.build -type d -name "release" 2>/dev/null && \
        exit 1; \
    fi && \
    mkdir -p /tmp/build-output && \
    cp "$RELEASE_DIR/Prospero" /tmp/build-output/Prospero && \
    mkdir -p /tmp/resources && \
    find "$RELEASE_DIR" -maxdepth 1 -type d -name "*.resources" \
        -exec cp -r {} /tmp/resources/ \; && \
    echo "Binary: $(file /tmp/build-output/Prospero)" && \
    echo "Resources:" && ls /tmp/resources/ 2>/dev/null || true

# ── Runtime stage ────────────────────────────────────────────────────────────

FROM ubuntu:24.04

ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION

LABEL org.opencontainers.image.vendor="Llamagraphics, Inc."
LABEL org.opencontainers.image.title="Prospero"
LABEL org.opencontainers.image.description="Reverse weather forecaster"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libcurl4 \
    libxml2 \
    tzdata \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime \
    && echo "America/New_York" > /etc/timezone

ENV TZ=America/New_York

# Copy Swift runtime libraries from the build stage so we don't need the
# full Swift image at runtime.
COPY --from=builder /usr/lib/swift/linux/ /usr/lib/swift/linux/

COPY --from=builder /tmp/build-output/Prospero /app/Prospero

# On Linux, Swift looks for .resources directories next to the executable.
COPY --from=builder /tmp/resources/ /app/

RUN useradd --create-home --shell /bin/bash app
WORKDIR /app
USER app

EXPOSE 8080

ENTRYPOINT ["./Prospero"]
CMD ["serve", "--hostname", "0.0.0.0", "--port", "8080"]
