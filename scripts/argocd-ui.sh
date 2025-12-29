#!/bin/bash
# argocd-ui.sh - Access ArgoCD UI with password
# Usage: ./scripts/argocd-ui.sh [port]
# Default port: 9090

set -euo pipefail

PORT="${1:-9090}"

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

# Wait for ArgoCD server to be ready
echo "Checking ArgoCD server..."
kubectl wait --for=condition=available --timeout=60s deployment/argocd-server -n argocd

# Kill any existing kubectl port-forward on the target port
echo "Checking port $PORT..."
pkill -9 -f "port-forward.*:$PORT:" 2>/dev/null || true
pkill -9 -f "port-forward.*$PORT:443" 2>/dev/null || true
sleep 1

# Check if port is still in use
if ss -tln | grep -q ":$PORT "; then
    echo ""
    echo "WARNING: Port $PORT is in use by another process."
    echo ""
    # Show what's using it
    ss -tlnp 2>/dev/null | grep ":$PORT " || true
    echo ""
    read -p "Try a different port? Enter port number (or 'q' to quit): " NEW_PORT
    if [[ "$NEW_PORT" == "q" ]]; then
        exit 1
    fi
    PORT="$NEW_PORT"
fi

# Get and display password
PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "========================================"
echo "Username: admin"
echo "Password: $PASSWORD"
echo "========================================"
echo ""
echo "URL: https://localhost:$PORT"
echo "(Accept the self-signed certificate warning in your browser)"
echo ""
echo "Starting port-forward (Ctrl+C to stop)..."
echo ""

# Start port-forward and verify it's working
kubectl port-forward svc/argocd-server -n argocd $PORT:443 &
PF_PID=$!
sleep 2

# Verify port-forward is working
if ! kill -0 $PF_PID 2>/dev/null; then
    echo "ERROR: Port-forward failed to start"
    exit 1
fi

# Test connection
if curl -sk --connect-timeout 5 "https://localhost:$PORT" >/dev/null 2>&1; then
    echo "Port-forward is working. ArgoCD UI available at https://localhost:$PORT"
    echo ""
    echo "Press Ctrl+C to stop..."
    wait $PF_PID
else
    echo "WARNING: Could not verify connection, but port-forward may still work."
    echo "Try opening https://localhost:$PORT in your browser."
    echo ""
    echo "Press Ctrl+C to stop..."
    wait $PF_PID
fi
