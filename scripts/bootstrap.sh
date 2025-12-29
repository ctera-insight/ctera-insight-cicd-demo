#!/bin/bash
# bootstrap.sh - Sets up the complete GitOps demo environment
# Usage: ./scripts/bootstrap.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo "Multi-Tenant GitOps Platform Bootstrap"
echo "========================================"
echo ""

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    local missing=()

    if ! command -v kind &> /dev/null; then
        missing+=("kind")
    fi

    if ! command -v kubectl &> /dev/null; then
        missing+=("kubectl")
    fi

    if ! command -v helm &> /dev/null; then
        missing+=("helm")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if ! command -v yq &> /dev/null; then
        echo "  Warning: yq not installed (optional but recommended)"
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing[*]}"
        echo ""
        echo "Install them using:"
        echo "  - kind: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "  - helm: https://helm.sh/docs/intro/install/"
        echo "  - jq: apt install jq / brew install jq"
        echo "  - yq: https://github.com/mikefarah/yq#install"
        exit 1
    fi

    echo "  All prerequisites installed!"
}

# Create Kind cluster
create_cluster() {
    echo ""
    echo "Creating Kind cluster..."

    if kind get clusters 2>/dev/null | grep -q "gitops-demo"; then
        echo "  Cluster 'gitops-demo' already exists"
        read -p "  Delete and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kind delete cluster --name gitops-demo
        else
            echo "  Using existing cluster"
            return
        fi
    fi

    # Create cluster with ingress ports mapped
    # Using K8s 1.31.0 for stability (default v1.35.0 has kubelet issues)
    cat <<EOF | kind create cluster --name gitops-demo --image kindest/node:v1.31.0 --config=-
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
}

# Install ArgoCD
install_argocd() {
    echo ""
    echo "Installing ArgoCD..."

    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    echo "  Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

    echo "  ArgoCD installed!"
}

# Get ArgoCD admin password
get_argocd_password() {
    echo ""
    echo "ArgoCD Admin Password:"
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    echo ""
}

# Apply AppProjects
apply_appprojects() {
    echo ""
    echo "Applying ArgoCD AppProjects..."

    for project in "$REPO_ROOT/argocd/appprojects"/*.yaml; do
        echo "  Applying $(basename "$project")..."
        kubectl apply -f "$project"
    done

    echo "  AppProjects applied!"
}

# Apply ApplicationSets
apply_applicationsets() {
    echo ""
    echo "Applying ArgoCD ApplicationSets..."

    for appset in "$REPO_ROOT/argocd"/applicationset-*.yaml; do
        echo "  Applying $(basename "$appset")..."
        kubectl apply -f "$appset"
    done

    echo "  ApplicationSets applied!"
}

# Install NGINX Ingress Controller
install_ingress() {
    echo ""
    echo "Installing NGINX Ingress Controller..."

    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

    echo "  Waiting for ingress controller to be ready..."
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=90s || true

    echo "  Ingress controller installed!"
}

# Print summary
print_summary() {
    echo ""
    echo "========================================"
    echo "Bootstrap Complete!"
    echo "========================================"
    echo ""
    echo "ArgoCD UI:"
    echo "  URL: https://localhost:8080"
    echo "  Username: admin"
    echo "  Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d")"
    echo ""
    echo "Port-forward ArgoCD (if not using ingress):"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo ""
    echo "Tenants configured:"
    for tenant in "$REPO_ROOT/tenants"/*/; do
        echo "  - $(basename "$tenant")"
    done
    echo ""
    echo "Next steps:"
    echo "  1. Push service repos (ui-service-demo, billing-service-demo) to GitHub"
    echo "  2. Create GitHub bot token with repo access"
    echo "  3. Add BOT_TOKEN secret to all repos"
    echo "  4. Push this config repo to trigger ArgoCD sync"
    echo ""
}

# Main
main() {
    check_prerequisites
    create_cluster
    install_argocd
    install_ingress
    apply_appprojects
    apply_applicationsets
    print_summary
}

main "$@"
