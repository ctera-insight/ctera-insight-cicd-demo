#!/bin/bash
# promote.sh - Promotes service versions from one environment to another
# Usage: ./scripts/promote.sh <from-env> <to-env>
# Example: ./scripts/promote.sh dev qa

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

FROM_ENV="${1:-}"
TO_ENV="${2:-}"

if [[ -z "$FROM_ENV" || -z "$TO_ENV" ]]; then
    echo "Error: Source and target environments required"
    echo "Usage: $0 <from-env> <to-env>"
    echo "Valid environments: dev, qa, staging, prod"
    exit 1
fi

# Validate promotion path
validate_promotion() {
    case "$FROM_ENV-$TO_ENV" in
        dev-qa|qa-staging|staging-prod)
            return 0
            ;;
        *)
            echo "Error: Invalid promotion path: $FROM_ENV -> $TO_ENV"
            echo "Valid paths: dev->qa, qa->staging, staging->prod"
            exit 1
            ;;
    esac
}

validate_promotion

FROM_CONFIG="$REPO_ROOT/env-types/$FROM_ENV/config.json"
TO_CONFIG="$REPO_ROOT/env-types/$TO_ENV/config.json"
FROM_VALUES="$REPO_ROOT/env-types/$FROM_ENV/values.yaml"
TO_VALUES="$REPO_ROOT/env-types/$TO_ENV/values.yaml"

if [[ ! -f "$FROM_CONFIG" ]]; then
    echo "Error: Source config not found: $FROM_CONFIG"
    exit 1
fi

if [[ ! -f "$TO_CONFIG" ]]; then
    echo "Error: Target config not found: $TO_CONFIG"
    exit 1
fi

echo "Promoting versions from $FROM_ENV to $TO_ENV"

# Extract service versions from source and update target
if command -v jq &> /dev/null; then
    # Get service versions from source
    UI_CHART_VERSION=$(jq -r '.services.ui.chartVersion' "$FROM_CONFIG")
    UI_IMAGE_TAG=$(jq -r '.services.ui.imageTag' "$FROM_CONFIG")
    BILLING_CHART_VERSION=$(jq -r '.services.billing.chartVersion' "$FROM_CONFIG")
    BILLING_IMAGE_TAG=$(jq -r '.services.billing.imageTag' "$FROM_CONFIG")

    echo "Versions to promote:"
    echo "  UI: chart=$UI_CHART_VERSION, image=$UI_IMAGE_TAG"
    echo "  Billing: chart=$BILLING_CHART_VERSION, image=$BILLING_IMAGE_TAG"

    # Update target config.json
    jq --arg ui_chart "$UI_CHART_VERSION" \
       --arg ui_image "$UI_IMAGE_TAG" \
       --arg billing_chart "$BILLING_CHART_VERSION" \
       --arg billing_image "$BILLING_IMAGE_TAG" \
       '.services.ui.chartVersion = $ui_chart |
        .services.ui.imageTag = $ui_image |
        .services.billing.chartVersion = $billing_chart |
        .services.billing.imageTag = $billing_image' \
        "$TO_CONFIG" > "$TO_CONFIG.tmp" && mv "$TO_CONFIG.tmp" "$TO_CONFIG"

    echo "Updated: $TO_CONFIG"
else
    echo "Error: jq is required for this script"
    exit 1
fi

# Update image tags in values.yaml
if command -v yq &> /dev/null; then
    yq eval ".services.ui.image.tag = \"$UI_IMAGE_TAG\"" -i "$TO_VALUES"
    yq eval ".services.billing.image.tag = \"$BILLING_IMAGE_TAG\"" -i "$TO_VALUES"
    echo "Updated: $TO_VALUES"
else
    echo "Warning: yq not installed. values.yaml not updated with new image tags"
fi

# Regenerate all tenant configs for target environment
echo ""
echo "Regenerating tenant configs for $TO_ENV environment..."
for tenant_dir in "$REPO_ROOT/tenants"/*-"$TO_ENV"; do
    if [[ -d "$tenant_dir" ]]; then
        tenant_name=$(basename "$tenant_dir")
        echo "  Regenerating: $tenant_name"
        "$SCRIPT_DIR/merge-values.sh" "$tenant_name"
    fi
done

echo ""
echo "Promotion complete: $FROM_ENV -> $TO_ENV"
echo "Commit and push to trigger ArgoCD sync"
