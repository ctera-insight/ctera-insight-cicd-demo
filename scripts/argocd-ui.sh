#!/bin/bash
# argocd-ui.sh - Access ArgoCD UI with password
# Usage: ./scripts/argocd-ui.sh

set -euo pipefail

echo "========================================"
echo "         ArgoCD UI Access"
echo "========================================"
echo ""

# Check if ArgoCD is running
if ! kubectl get namespace argocd &>/dev/null; then
    echo "Error: ArgoCD namespace not found. Run ./scripts/bootstrap.sh first."
    exit 1
fi

if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
    echo "Error: ArgoCD server not deployed."
    exit 1
fi

# Get and display password
echo "Username: admin"
echo -n "Password: "
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "URL: https://localhost:8080"
echo ""
echo "Starting port-forward (Ctrl+C to stop)..."
echo "========================================"
echo ""

# Start port-forward
kubectl port-forward svc/argocd-server -n argocd 8080:443
