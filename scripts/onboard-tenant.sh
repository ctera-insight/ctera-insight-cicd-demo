#!/bin/bash
# onboard-tenant.sh - Creates a new tenant with all required config files
# Usage: ./scripts/onboard-tenant.sh <tenant-name> <env-type>
# Example: ./scripts/onboard-tenant.sh customer2 qa

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

CUSTOMER_NAME="${1:-}"
ENV_TYPE="${2:-}"

if [[ -z "$CUSTOMER_NAME" || -z "$ENV_TYPE" ]]; then
    echo "Error: Customer name and environment type required"
    echo "Usage: $0 <customer-name> <env-type>"
    echo "Examples:"
    echo "  $0 customer2 dev     # Creates customer2-dev tenant"
    echo "  $0 john dev          # Creates dev-john tenant (developer format)"
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

# Determine tenant name format
# For dev environment with single-word names, use dev-<name> format (developer env)
# For all others, use <customer>-<env> format
if [[ "$ENV_TYPE" == "dev" && ! "$CUSTOMER_NAME" =~ ^customer ]]; then
    TENANT_NAME="dev-$CUSTOMER_NAME"
else
    TENANT_NAME="$CUSTOMER_NAME-$ENV_TYPE"
fi

TENANT_DIR="$REPO_ROOT/tenants/$TENANT_NAME"

if [[ -d "$TENANT_DIR" ]]; then
    echo "Error: Tenant already exists: $TENANT_DIR"
    exit 1
fi

echo "Creating new tenant: $TENANT_NAME"
echo "  Customer: $CUSTOMER_NAME"
echo "  Environment: $ENV_TYPE"
echo "  Namespace: ns-$TENANT_NAME"
echo ""

# Create tenant directory
mkdir -p "$TENANT_DIR"

# Create overrides.yaml with basic tenant-specific config
cat > "$TENANT_DIR/overrides.yaml" << EOF
# Layer 3: Tenant-specific overrides for $TENANT_NAME
global:
  namespace: ns-$TENANT_NAME

services:
  ui:
    ingress:
      domain: $CUSTOMER_NAME.$ENV_TYPE.local
EOF

echo "Created: $TENANT_DIR/overrides.yaml"

# Generate merged values and config.json
"$SCRIPT_DIR/merge-values.sh" "$TENANT_NAME"

echo ""
echo "Tenant $TENANT_NAME created successfully!"
echo ""
echo "Files created:"
echo "  - $TENANT_DIR/overrides.yaml (edit for tenant customizations)"
echo "  - $TENANT_DIR/values.yaml (auto-generated merged values)"
echo "  - $TENANT_DIR/config.json (auto-generated for ApplicationSet)"
echo ""
echo "Next steps:"
echo "  1. Review and customize overrides.yaml if needed"
echo "  2. git add tenants/$TENANT_NAME"
echo "  3. git commit -m 'Onboard tenant $TENANT_NAME'"
echo "  4. git push"
echo "  5. ArgoCD will auto-create applications for this tenant"
