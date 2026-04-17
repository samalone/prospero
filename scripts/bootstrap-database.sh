#!/bin/bash
# Create the `prospero` Postgres role and database inside the shared
# postgres pod in the `life-balance` namespace. Run once per cluster
# (dev and prod each).
#
# The password is pulled from 1Password and sent in via STDIN to psql,
# so it never appears in process arguments or shell history.
#
# Usage:
#   ./scripts/bootstrap-database.sh dev    # docker-desktop context
#   ./scripts/bootstrap-database.sh prod   # pc (Linode) context

set -euo pipefail

ENV="${1:-}"
case "$ENV" in
    dev)  KCTX=docker-desktop; OP_ITEM=prospero-dev ;;
    prod) KCTX=pc;             OP_ITEM=prospero-production ;;
    *)    echo "Usage: $0 [dev|prod]" >&2; exit 1 ;;
esac

if ! command -v op &> /dev/null; then
    echo "Error: 1Password CLI (op) not installed." >&2
    exit 1
fi
if ! op account list --account my.1password.com &> /dev/null; then
    echo "Error: Not signed in to 1Password." >&2
    exit 1
fi

# Fetch the Prospero user's password (stored separately from the URL so
# we can use it here without parsing the URL).
PW=$(op read --account my.1password.com \
    "op://llama-infrastructure/$OP_ITEM/password")

if [[ -z "$PW" ]]; then
    echo "Error: empty password from 1Password item $OP_ITEM." >&2
    echo "Item must have a 'password' field with the role password." >&2
    exit 1
fi

# Find the postgres pod in the life-balance namespace.
POD=$(kubectl --context "$KCTX" -n life-balance get pods \
    -l app=postgres -o name 2>/dev/null | head -1)
if [[ -z "$POD" ]]; then
    # Older manifests may not label pods — fall back to name match.
    POD=$(kubectl --context "$KCTX" -n life-balance get pods \
        -o name | grep -E 'postgres' | head -1)
fi
if [[ -z "$POD" ]]; then
    echo "Error: no postgres pod found in life-balance namespace on $KCTX." >&2
    exit 1
fi

echo "Bootstrapping Prospero database on $KCTX ($POD)..."

# Create the role and database idempotently. The role is owner so it can
# run migrations without separate GRANTs.
kubectl --context "$KCTX" -n life-balance exec -i "$POD" -- \
    psql -U postgres -v ON_ERROR_STOP=1 -v password="$PW" <<'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'prospero') THEN
        EXECUTE format('CREATE ROLE prospero LOGIN PASSWORD %L', :'password');
    ELSE
        EXECUTE format('ALTER ROLE prospero WITH LOGIN PASSWORD %L', :'password');
    END IF;
END $$;

SELECT 'CREATE DATABASE prospero OWNER prospero'
 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'prospero')\gexec
SQL

echo "Done."
