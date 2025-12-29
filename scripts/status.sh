#!/bin/bash
# status.sh - Show cluster and ArgoCD status
# Usage: ./scripts/status.sh

set -euo pipefail

echo "========================================"
echo "      GitOps Platform Status"
echo "========================================"

# Cluster status
echo ""
echo "=== Cluster ==="
if kubectl cluster-info &>/dev/null; then
    CONTEXT=$(kubectl config current-context)
    echo "Context: $CONTEXT"
    kubectl get nodes -o wide 2>/dev/null || echo "No nodes found"
else
    echo "Cluster not accessible"
    exit 1
fi

# ArgoCD status
echo ""
echo "=== ArgoCD Pods ==="
if kubectl get namespace argocd &>/dev/null; then
    kubectl get pods -n argocd --no-headers 2>/dev/null | while read line; do
        echo "  $line"
    done
else
    echo "  ArgoCD not installed"
fi

# ApplicationSets
echo ""
echo "=== ApplicationSets ==="
if kubectl get applicationsets -n argocd &>/dev/null; then
    COUNT=$(kubectl get applicationsets -n argocd --no-headers 2>/dev/null | wc -l)
    if [[ "$COUNT" -gt 0 ]]; then
        kubectl get applicationsets -n argocd --no-headers 2>/dev/null | while read line; do
            echo "  $line"
        done
    else
        echo "  No ApplicationSets found"
    fi
else
    echo "  Cannot list ApplicationSets"
fi

# Applications
echo ""
echo "=== Applications ==="
if kubectl get applications -n argocd &>/dev/null; then
    COUNT=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
    if [[ "$COUNT" -gt 0 ]]; then
        kubectl get applications -n argocd --no-headers 2>/dev/null | while read line; do
            echo "  $line"
        done
    else
        echo "  No Applications found (push config repo to GitHub to create)"
    fi
else
    echo "  Cannot list Applications"
fi

# AppProjects
echo ""
echo "=== AppProjects ==="
kubectl get appprojects -n argocd --no-headers 2>/dev/null | while read line; do
    echo "  $line"
done

# Namespaces (tenant namespaces)
echo ""
echo "=== Tenant Namespaces ==="
kubectl get namespaces --no-headers 2>/dev/null | grep "^ns-" | while read line; do
    echo "  $line"
done || echo "  No tenant namespaces yet"

echo ""
echo "========================================"
