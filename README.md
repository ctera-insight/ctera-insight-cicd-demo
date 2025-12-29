# Multi-Tenant GitOps Platform Demo

A production-ready POC for multi-tenant GitOps using Helm, ArgoCD, and GitHub Actions.

## Features

- **Single Source of Truth**: All tenant configurations in one repository
- **Three-Layer Hierarchy**: base → environment-type → tenant overrides
- **Namespace Isolation**: Each tenant gets its own Kubernetes namespace
- **PR Isolation**: Developers test changes in personal namespaces
- **Cascading Updates**: Environment-type changes propagate to all tenants
- **Sequential Promotion**: dev → qa → staging → prod with approval gates
- **Auto-Onboarding**: New tenants auto-deployed via ArgoCD ApplicationSets
- **Git-Based Rollback**: Revert by changing versions in Git

## Quick Start

```bash
# Bootstrap the demo environment
./scripts/bootstrap.sh

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
```

See [SETUP.md](SETUP.md) for detailed setup instructions.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     GitHub Actions CI/CD                         │
├─────────────────┬─────────────────┬─────────────────────────────┤
│ ui-service-demo │ billing-service │ ctera-insight-cicd-demo     │
│   (Helm chart)  │   (Helm chart)  │ (Config repo)               │
└────────┬────────┴────────┬────────┴──────────────┬──────────────┘
         │                 │                       │
         │    Push tags    │                       │ Update configs
         ▼                 ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                         ArgoCD                                   │
│  ┌──────────────┐  ┌──────────────────────────────────────┐     │
│  │ AppProjects  │  │ ApplicationSets                       │     │
│  │ dev/qa/      │  │ - ui-service (generates apps/tenant)  │     │
│  │ staging/prod │  │ - billing-service                     │     │
│  └──────────────┘  └──────────────────────────────────────┘     │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                            │
│  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐       │
│  │ ns-dev-john    │ │ ns-customer1-  │ │ ns-customer1-  │       │
│  │ (developer)    │ │ dev            │ │ prod           │       │
│  │                │ │                │ │                │       │
│  │ ┌────┐ ┌────┐  │ │ ┌────┐ ┌────┐  │ │ ┌────┐ ┌────┐  │       │
│  │ │ UI │ │Bill│  │ │ │ UI │ │Bill│  │ │ │ UI │ │Bill│  │       │
│  │ └────┘ └────┘  │ │ └────┘ └────┘  │ │ └────┘ └────┘  │       │
│  └────────────────┘ └────────────────┘ └────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
```

## Value Hierarchy

```yaml
# Layer 1: bases/values.yaml (Platform defaults)
global:
  security:
    enabled: true

# Layer 2: env-types/dev/values.yaml (Environment defaults)
global:
  replicas: 1
  debug: true

# Layer 3: tenants/dev-john/overrides.yaml (Tenant overrides)
services:
  ui:
    ingress:
      domain: john.dev.local
```

## Demo Scenarios

| Scenario | Command/Action |
|----------|----------------|
| Onboard tenant | `./scripts/onboard-tenant.sh customer2 qa` |
| PR isolation | Open PR in ui-service-demo |
| Merge & cascade | Merge PR → auto-updates all dev tenants |
| Promote | GitHub Actions → "Promote Environment" |
| Rollback | Edit env-type config → push |

## Repository Structure

```
├── bases/                    # Platform-wide defaults
├── env-types/               # Per-environment defaults + versions
│   ├── dev/
│   ├── qa/
│   ├── staging/
│   └── prod/
├── tenants/                 # Per-tenant overrides
│   ├── dev-john/
│   ├── customer1-dev/
│   └── ...
├── argocd/                  # ArgoCD configurations
├── scripts/                 # Automation scripts
└── service-repos/           # Templates for service repos
```

## Related Repositories

- [ui-service-demo](https://github.com/ctera-insight/ui-service-demo) - UI microservice
- [billing-service-demo](https://github.com/ctera-insight/billing-service-demo) - Billing microservice

## Requirements

- Docker
- Kind or Minikube
- kubectl
- Helm v3+
- jq
- yq (optional)
