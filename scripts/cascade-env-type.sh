#!/bin/bash
# cascade-env-type.sh - Regenerates all tenant configs for a given environment type
# Called when env-types/<env>/config.json or values.yaml changes
# Usage: ./scripts/cascade-env-type.sh <env-type>
# Example: ./scripts/cascade-env-type.sh dev

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

ENV_TYPE="${1:-}"

if [[ -z "$ENV_TYPE" ]]; then
    echo "Error: Environment type required"
    echo "Usage: $0 <env-type>"
    echo "Valid types: dev, qa, staging, prod"
    exit 1
fi

# Validate env type
case "$ENV_TYPE" in
    dev|qa|staging|prod)
        ;;
    *)
        echo "Error: Invalid environment type: $ENV_TYPE"
        echo "Valid types: dev, qa, staging, prod"
        exit 1
        ;;
esac

echo "Cascading changes to all $ENV_TYPE tenants..."

FOUND_TENANTS=0

# Find all tenants for this env type
# Pattern 1: dev-* (developer personal envs)
# Pattern 2: *-<env> (customer envs)
for tenant_dir in "$REPO_ROOT/tenants"/*; do
    if [[ ! -d "$tenant_dir" ]]; then
        continue
    fi

    tenant_name=$(basename "$tenant_dir")
    tenant_env=""

    # Determine env type from tenant name
    if [[ "$tenant_name" == dev-* ]]; then
        tenant_env="dev"
    elif [[ "$tenant_name" == *-dev ]]; then
        tenant_env="dev"
    elif [[ "$tenant_name" == *-qa ]]; then
        tenant_env="qa"
    elif [[ "$tenant_name" == *-staging ]]; then
        tenant_env="staging"
    elif [[ "$tenant_name" == *-prod ]]; then
        tenant_env="prod"
    fi

    if [[ "$tenant_env" == "$ENV_TYPE" ]]; then
        echo "  Regenerating: $tenant_name"
        "$SCRIPT_DIR/merge-values.sh" "$tenant_name"
        ((FOUND_TENANTS++))
    fi
done

echo ""
echo "Cascade complete: Updated $FOUND_TENANTS tenant(s) for $ENV_TYPE environment"
