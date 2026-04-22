#!/bin/bash
# Start a Tailscale-exposed dev instance of Prospero for mobile testing.
#
# Why this exists: passkeys require HTTPS and a stable hostname, so we
# can't just hit the dev server over LAN from the phone. Tailscale Serve
# publishes this Mac's localhost:8080 over a real Let's Encrypt-backed
# https://<machine>.<tailnet>.ts.net URL that our phone (on the same
# tailnet) can reach. No k8s, no public exposure, no build-and-push loop.
#
# Prerequisites (one-time):
#   1. Install Tailscale CLI on this Mac and sign in.
#   2. In the Tailscale admin console (https://login.tailscale.com/admin/dns):
#        - Enable MagicDNS.
#        - Enable HTTPS Certificates.
#   3. Install Tailscale on your phone and sign in to the same tailnet.
#
# Use:
#   scripts/tailscale-dev.sh              # starts server + serves over tailnet
#   tailscale serve reset                 # tears down the proxy when done
#
# On first run against a fresh dev database, the script auto-generates
# an invitation for samalone@llamagraphics.com and prints the URL.
# Subsequent runs are no-ops on the invite front — the existing user
# just signs in with their staging passkey.
#
# The WebAuthn RP ID is bound to the tailnet hostname, so the passkey
# you register here is separate from the one on propercourse.app —
# intentional. It'll stay valid across branches since your tailnet
# hostname never changes.

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v tailscale >/dev/null 2>&1; then
    echo "Error: tailscale CLI not found. Install Tailscale and sign in." >&2
    exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq not found. brew install jq." >&2
    exit 1
fi
if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "Error: sqlite3 CLI not found (it ships with macOS by default)." >&2
    exit 1
fi

FQDN=$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//')
if [[ -z "$FQDN" || "$FQDN" == "null" ]]; then
    echo "Error: could not determine Tailscale FQDN. Is tailscaled running?" >&2
    echo "Run 'tailscale status' to diagnose." >&2
    exit 1
fi

# Port 8443, not 443. Docker Desktop (and any other local app binding
# `*:443` on this Mac) would otherwise swallow incoming tailnet traffic
# before Tailscale Serve could handle it. WebAuthn handles non-default
# ports as long as the RP origin matches exactly.
SERVE_PORT=8443
DEV_URL="https://$FQDN:$SERVE_PORT"
DATA_DIR="${DATA_DIR:-$HOME/.prospero-dev}"
mkdir -p "$DATA_DIR"

echo "==> Dev URL:   $DEV_URL"
echo "==> Data dir:  $DATA_DIR"

# Replace any prior serve config with a single HTTPS → localhost forward.
echo "==> Configuring Tailscale Serve on port $SERVE_PORT…"
tailscale serve reset >/dev/null 2>&1 || true
tailscale serve --bg --https=$SERVE_PORT http://127.0.0.1:8080

echo ""
echo "==> Tailscale Serve is forwarding $DEV_URL → http://127.0.0.1:8080"
echo "    Stop it later with: tailscale serve reset"
echo ""

# RP_ID is the bare hostname; RP_ORIGIN is the full https URL. Both
# must match what the browser sees or WebAuthn ceremony fails.
export WEBAUTHN_RP_ID="$FQDN"
export WEBAUTHN_RP_ORIGIN="$DEV_URL"
export DATA_DIR

# First-run bootstrap: if there are no registered users, auto-generate
# an invitation so we don't have to juggle two terminals for it.
# Running migrations up front gives us a schema to query; migrations
# are idempotent so a second run is a no-op.
DB_PATH="$DATA_DIR/prospero.sqlite"
if [[ ! -f "$DB_PATH" ]] || ! sqlite3 "$DB_PATH" \
    "SELECT 1 FROM sqlite_master WHERE type='table' AND name='users'" \
    2>/dev/null | grep -q 1
then
    echo "==> Initializing dev database (running migrations)…"
    swift run Prospero migrate
fi

USER_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users")
if [[ "$USER_COUNT" -eq 0 ]]; then
    echo ""
    echo "==> No registered users yet. Generating invitation…"
    INVITE_OUT=$(mktemp)
    trap 'rm -f "$INVITE_OUT"' EXIT
    swift run Prospero invite \
        --email samalone@llamagraphics.com \
        --base-url "$DEV_URL" \
        --expires-days 30 | tee "$INVITE_OUT"
    INVITE_URL=$(awk '/URL:/ {print $2}' "$INVITE_OUT")
    if [[ -n "$INVITE_URL" ]] && command -v pbcopy >/dev/null 2>&1; then
        printf '%s' "$INVITE_URL" | pbcopy
        echo "==> Invitation URL copied to clipboard."
    fi
    echo ""
fi

echo "==> Starting prospero serve (auto-migrate)…"
echo "    Press Ctrl-C to stop."
exec swift run Prospero serve --auto-migrate --hostname 127.0.0.1 --port 8080
