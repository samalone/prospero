#!/bin/bash
# Inject secrets from 1Password into Kubernetes manifest files.
#
# Uses `op inject` to replace `op://` references in the template files
# with actual secret values from the llama-infrastructure vault, then
# writes the result alongside the template as a gitignored `secrets.yaml`.
#
# Required 1Password items (vault: llama-infrastructure):
#   - prospero-dev         field: database-url-base64
#   - prospero-production  field: database-url-base64
#
# Both fields should contain the base64 encoding of a Postgres URL of
# the form:
#   postgresql://prospero:PASSWORD@postgres.life-balance.svc.cluster.local:5432/prospero
#
# Usage:
#   ./scripts/inject-secrets.sh             # both environments
#   ./scripts/inject-secrets.sh dev         # dev only
#   ./scripts/inject-secrets.sh prod        # prod only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v op &> /dev/null; then
    echo "Error: 1Password CLI (op) not installed." >&2
    echo "Install from: https://developer.1password.com/docs/cli/get-started" >&2
    exit 1
fi

if ! op account list --account my.1password.com &> /dev/null; then
    echo "Error: Not signed in to 1Password (my.1password.com)." >&2
    echo "Run: eval \$(op signin --account my.1password.com)" >&2
    exit 1
fi

inject_for() {
    local env=$1
    local dir="$PROJECT_ROOT/k8s/overlays/$env"
    local template="$dir/secrets.yaml.template"
    local output="$dir/secrets.yaml"

    if [[ ! -f "$template" ]]; then
        echo "Skipping $env — no template at $template" >&2
        return 0
    fi

    echo "Injecting $env secrets..."
    op inject \
        --account my.1password.com \
        --in-file "$template" \
        --out-file "$output"
    echo "  -> $output"
}

case "${1:-all}" in
    all)
        inject_for dev
        inject_for prod
        ;;
    dev|prod)
        inject_for "$1"
        ;;
    *)
        echo "Usage: $0 [dev|prod|all]" >&2
        exit 1
        ;;
esac

echo "Done."
