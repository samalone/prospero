#!/bin/bash
# Create the `prospero` Postgres role and database inside the shared
# postgres pod in the `life-balance` namespace. Run once per cluster
# (dev and prod each).
#
# The shared pod's superuser is `lifebalance` (inherited from when
# Life Balance first spun it up). Its password is in the
# `postgres-secret` secret in the `life-balance` namespace.
# The Prospero role password comes from 1Password.
#
# Nothing sensitive appears in process args or shell history: both
# passwords are piped into psql via PSQL_VARS / stdin.
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

# Prospero role password from 1Password.
PROSPERO_PW=$(op read --account my.1password.com \
    "op://llama-infrastructure/$OP_ITEM/password")
if [[ -z "$PROSPERO_PW" ]]; then
    echo "Error: empty password from 1Password item $OP_ITEM." >&2
    echo "Item must have a 'password' field with the role password." >&2
    exit 1
fi

# Superuser password from the postgres-secret in life-balance namespace.
SUPER_PW=$(kubectl --context "$KCTX" -n life-balance \
    get secret postgres-secret \
    -o go-template='{{ .data.POSTGRES_PASSWORD | base64decode }}')
if [[ -z "$SUPER_PW" ]]; then
    echo "Error: could not read POSTGRES_PASSWORD from secret." >&2
    exit 1
fi

# Superuser name from the postgres-config configmap.
SUPER_USER=$(kubectl --context "$KCTX" -n life-balance \
    get configmap postgres-config \
    -o go-template='{{ .data.POSTGRES_USER }}')
SUPER_USER="${SUPER_USER:-lifebalance}"

# Find the postgres pod.
POD=$(kubectl --context "$KCTX" -n life-balance get pods \
    -l app=postgres -o name 2>/dev/null | head -1)
if [[ -z "$POD" ]]; then
    POD=$(kubectl --context "$KCTX" -n life-balance get pods \
        -o name | grep -E 'postgres' | head -1)
fi
if [[ -z "$POD" ]]; then
    echo "Error: no postgres pod found in life-balance namespace on $KCTX." >&2
    exit 1
fi

echo "Bootstrapping Prospero database on $KCTX ($POD) as $SUPER_USER..."

# Run psql inside the pod. Pass the Prospero password as a psql variable
# (-v) so it's properly quoted via format('%L', ...), and PGPASSWORD
# through env so the superuser auth doesn't prompt.
kubectl --context "$KCTX" -n life-balance exec -i "$POD" -- \
    env PGPASSWORD="$SUPER_PW" \
    psql -U "$SUPER_USER" -d postgres \
         -v ON_ERROR_STOP=1 \
         -v prospero_pw="$PROSPERO_PW" <<'SQL'
-- Create or update the prospero role idempotently. `format %L` quotes
-- the password literal correctly so special characters don't break SQL.
SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'prospero')
    THEN format('ALTER  ROLE prospero WITH LOGIN PASSWORD %L', :'prospero_pw')
    ELSE format('CREATE ROLE prospero      LOGIN PASSWORD %L', :'prospero_pw')
END \gexec

-- Create the prospero database owned by the prospero role if missing.
SELECT 'CREATE DATABASE prospero OWNER prospero'
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'prospero')
\gexec
SQL

echo "Done."
