# Multi-Tenant GitOps Platform - Setup Guide

This guide walks you through setting up the complete GitOps demo environment.

## Prerequisites

Install the following tools:

```bash
# Kind (Kubernetes in Docker)
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# jq
sudo apt install jq  # or: brew install jq

# yq (optional but recommended)
sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
sudo chmod +x /usr/local/bin/yq
```

## Quick Start

Run the bootstrap script to set up everything:

```bash
./scripts/bootstrap.sh
```

This will:
1. Create a Kind cluster named `gitops-demo`
2. Install ArgoCD
3. Install NGINX Ingress Controller
4. Apply AppProjects for dev/qa/staging/prod
5. Apply ApplicationSets for UI and Billing services

## Manual Setup

### 1. Create Kind Cluster

```bash
kind create cluster --name gitops-demo
```

### 2. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 3. Access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080 (accept the self-signed certificate)
- Username: `admin`
- Password: (from step 2)

### 4. Apply ArgoCD Configs

```bash
# Apply AppProjects
kubectl apply -f argocd/appprojects/

# Apply ApplicationSets
kubectl apply -f argocd/applicationset-ui.yaml
kubectl apply -f argocd/applicationset-billing.yaml
```

## GitHub Setup

### 1. Create Service Repos

The `service-repos/` directory contains templates for the UI and Billing services. Create new GitHub repos and push:

```bash
# UI Service
cd service-repos/ui-service-demo
git init
git remote add origin https://github.com/ctera-insight/ui-service-demo.git
git add .
git commit -m "Initial commit"
git push -u origin main

# Billing Service
cd ../billing-service-demo
git init
git remote add origin https://github.com/ctera-insight/billing-service-demo.git
git add .
git commit -m "Initial commit"
git push -u origin main
```

### 2. Create GitHub Bot Token

1. Go to GitHub Settings → Developer settings → Personal access tokens → Fine-grained tokens
2. Create a new token with:
   - Repository access: Select the 3 repos
   - Permissions:
     - Contents: Read and write
     - Pull requests: Read and write
     - Workflows: Read and write

### 3. Add Secrets to Repos

Add `BOT_TOKEN` secret to all three repos:
1. Go to repo Settings → Secrets and variables → Actions
2. Add new secret named `BOT_TOKEN` with the token value

### 4. Push Config Repo

```bash
git add .
git commit -m "Initial GitOps platform setup"
git push
```

## Demo Flows

### 1. Tenant Onboarding

Via GitHub Actions:
1. Go to Actions → "Onboard New Tenant"
2. Click "Run workflow"
3. Enter customer name and environment type
4. Watch ArgoCD create the new app

Via CLI:
```bash
./scripts/onboard-tenant.sh customer2 qa
git add tenants/customer2-qa
git commit -m "Onboard customer2-qa"
git push
```

### 2. PR Isolation Testing

1. Create a branch in ui-service-demo
2. Make changes and open a PR
3. GitHub Actions builds PR-tagged image
4. Updates your dev-<username> tenant
5. ArgoCD syncs changes to your isolated namespace

### 3. Merge & Cascade

1. Merge PR to main
2. GitHub Actions builds release image
3. Updates env-types/dev/config.json
4. Cascade workflow regenerates all dev tenant configs
5. ArgoCD syncs all dev tenants with new version

### 4. Promotion

Via GitHub Actions:
1. Go to Actions → "Promote Environment"
2. Select source and target (e.g., dev → qa)
3. Approve if target is staging/prod
4. Watch all target env tenants update

Via CLI:
```bash
./scripts/promote.sh dev qa
git add .
git commit -m "Promote dev to qa"
git push
```

### 5. Rollback

```bash
# Edit env-type config to previous version
vim env-types/qa/config.json

# Regenerate tenant configs
./scripts/cascade-env-type.sh qa

# Commit and push
git add .
git commit -m "Rollback qa to v0.1.0"
git push

# ArgoCD automatically syncs to previous version
```

## Directory Structure

```
ctera-insight-cicd-demo/
├── bases/                    # Layer 1: Platform defaults
│   └── values.yaml
├── env-types/               # Layer 2: Environment defaults
│   ├── dev/
│   │   ├── config.json      # Service versions (for ApplicationSet)
│   │   └── values.yaml      # Environment values
│   ├── qa/
│   ├── staging/
│   └── prod/
├── tenants/                 # Layer 3: Tenant overrides
│   ├── dev-john/
│   │   ├── config.json      # Generated for ApplicationSet
│   │   ├── values.yaml      # Merged values (auto-generated)
│   │   └── overrides.yaml   # Tenant customizations
│   ├── customer1-dev/
│   ├── customer1-qa/
│   └── ...
├── argocd/
│   ├── appprojects/         # RBAC per environment
│   ├── applicationset-ui.yaml
│   └── applicationset-billing.yaml
├── scripts/
│   ├── bootstrap.sh         # Initial setup
│   ├── merge-values.sh      # Merge 3 layers
│   ├── promote.sh           # Env promotion
│   ├── cascade-env-type.sh  # Update all tenants
│   └── onboard-tenant.sh    # New tenant
├── .github/workflows/
│   ├── cascade-env-type.yaml
│   ├── promote.yaml
│   └── onboard-tenant.yaml
└── service-repos/           # Templates for service repos
    ├── ui-service-demo/
    └── billing-service-demo/
```

## Troubleshooting

### ArgoCD sync fails

```bash
# Check ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# Check application status
kubectl get applications -n argocd

# Describe specific application
kubectl describe application <app-name> -n argocd
```

### Tenant not appearing

1. Check config.json is valid JSON: `jq . tenants/<tenant>/config.json`
2. Verify ApplicationSet is detecting files: `kubectl get applicationsets -n argocd`
3. Check ApplicationSet events: `kubectl describe applicationset -n argocd`

### CI workflow fails

1. Check BOT_TOKEN is set in repository secrets
2. Verify token has correct permissions
3. Check workflow logs in GitHub Actions

### Values not merging correctly

```bash
# Test merge locally
./scripts/merge-values.sh <tenant-name>

# Verify output
cat tenants/<tenant-name>/values.yaml
```
