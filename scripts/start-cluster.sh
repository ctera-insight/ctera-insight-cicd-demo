#!/bin/bash
# start-cluster.sh - Ensure Kind cluster is running
# Usage: ./scripts/start-cluster.sh

set -euo pipefail

CLUSTER_NAME="gitops-demo"
K8S_VERSION="kindest/node:v1.31.0"

echo "========================================"
echo "     GitOps Demo Cluster Startup"
echo "========================================"
echo ""

# Check Docker
echo "Checking Docker..."
if ! docker info &>/dev/null; then
    echo "Error: Docker is not running. Please start Docker first."
    exit 1
fi
echo "  Docker is running"

# Check if cluster exists
echo ""
echo "Checking Kind cluster..."
if kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    echo "  Cluster '$CLUSTER_NAME' exists"

    # Check if cluster is accessible
    if kubectl cluster-info --context "kind-$CLUSTER_NAME" &>/dev/null; then
        echo "  Cluster is accessible"
    else
        echo "  Cluster exists but not accessible. It may need to be recreated."
        echo ""
        read -p "  Recreate cluster? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kind delete cluster --name "$CLUSTER_NAME"
        else
            exit 1
        fi
    fi
else
    echo "  Cluster '$CLUSTER_NAME' not found. Creating..."

    cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --image "$K8S_VERSION" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
EOF
    echo "  Cluster created!"
fi

# Set context
echo ""
echo "Setting kubectl context..."
kubectl config use-context "kind-$CLUSTER_NAME"
echo "  Context set to kind-$CLUSTER_NAME"

# Check ArgoCD
echo ""
echo "Checking ArgoCD..."
if kubectl get namespace argocd &>/dev/null; then
    READY=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$READY" == "1" ]]; then
        echo "  ArgoCD is running"
    else
        echo "  ArgoCD is installed but not ready. Waiting..."
        kubectl wait --for=condition=available --timeout=120s deployment/argocd-server -n argocd
    fi
else
    echo "  ArgoCD not installed. Run ./scripts/bootstrap.sh to install."
fi

echo ""
echo "========================================"
echo "Cluster is ready!"
echo ""
echo "Next steps:"
echo "  ./scripts/status.sh     - View cluster status"
echo "  ./scripts/argocd-ui.sh  - Access ArgoCD UI"
echo "========================================"
