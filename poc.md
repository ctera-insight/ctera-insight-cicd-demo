You are tasked with implementing a full demo Proof of Concept (POC) for a Multi-Tenant GitOps Platform using Helm for configuration layering and service packaging, ArgoCD for GitOps orchestration, and GitHub Actions for CI/CD automation. The platform must support 29 specific requirements, including a single repository for all tenant configs, a three-layer hierarchy (base → environment types → tenant overrides), a single Kubernetes cluster with isolated namespaces, developer workflows with isolated PR testing, controlled sequential promotions (dev → qa → staging → prod), cascading changes per env-type, single ArgoCD Application per tenant, full automation via CI, and Git-based versioning/rollback.
The goal is to create a working demo with at least two services (UI and Billing from separate repos), multiple tenants (e.g., developer personal envs and customer staged envs), and showcase flows like PR isolation, merging, promotion, and onboarding. Use a local Minikube or Kind cluster for the POC, but design for scalability to a real cluster like EKS.
Step 1: Setup Prerequisites

Install Helm (v3+), kubectl, Git, and ArgoCD CLI.
Create a local K8s cluster: minikube start or kind create cluster.
Install ArgoCD: kubectl create namespace argocd && kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml. Access UI: kubectl port-forward svc/argocd-server -n argocd 8080:443 (login with admin/initial password from pod).
Create GitHub repos: cluster-01-tenants (main config repo), ui-repo (UI service Helm chart), billing-repo (Billing service Helm chart).
Generate a GitHub bot token for CI commits (fine-grained, with repo access).

Step 2: Directory Structure in cluster-01-tenants
This repo is the single source of truth (#1). Structure enforces the three-layer model (#2):

bases/: Layer 1 - Platform-wide defaults (one values.yaml for globals like security/quotas).
env-types/: Layer 2 - Env-specific defaults with service versions (one values.yaml per env, nested sections for services like UI/Billing; changes cascade to tenants #19).
tenants/: Layer 3 - Per-tenant-env overrides (one values.yaml per tenant, flat structure for independence #9; selective overrides #18, #20).
argocd/: ArgoCD configs for auto-onboarding and isolation.

Full structure:
textcluster-01-tenants/
├── bases/
│   └── values.yaml  # Platform globals
├── env-types/
│   ├── dev/
│   │   └── values.yaml  # Dev defaults + service versions
│   ├── qa/
│   │   └── values.yaml
│   ├── staging/
│   │   └── values.yaml
│   └── prod/
│       └── values.yaml
├── tenants/
│   ├── dev-john/  # Developer personal env (#5)
│   │   └── values.yaml
│   ├── customer1-dev/
│   │   └── values.yaml
│   ├── customer1-qa/
│   │   └── values.yaml
│   ├── customer1-staging/
│   │   └── values.yaml
│   └── customer1-prod/
│       └── values.yaml
├── argocd/
│   ├── appprojects.yaml  # RBAC isolation per env-type
│   └── applicationset.yaml  # Auto-generates one App per tenant (#21, #25)
└── .github/workflows/
    ├── pr-validation.yaml  # Isolate PR tests (#16)
    ├── merge-dev.yaml  # Cascade to dev (#17, #19)
    └── promote.yaml  # Gated promotions (#7-10)
Step 3: Example values.yaml Files
Use flattened single values.yaml per layer/base/env-type/tenant, with nested services sections for UI and Billing.

bases/values.yaml (Layer 1):textglobal:
  clusterName: cluster-01
  security:
    enabled: true
    networkPolicy: denyAll
  quotas:
    cpu: 10
    memory: 20Gi
env-types/dev/values.yaml (Layer 2):textglobal:  # Overrides base
  replicas: 1
  debug: true
services:  # Versions for UI (microservice + Ingress) and Billing (microservice + Flink pipeline #13)
  ui:
    chartVersion: v1.2.0
    image:
      repo: org/ui
      tag: v1.2.0
    microservice:
      enabled: true
    ingress:
      domain: dev.example.com
  billing:
    chartVersion: v2.1.0
    image:
      repo: org/billing
      tag: v2.1.0
    pipeline:
      flink:
        enabled: true
        parallelism: 2
        checkpointInterval: 60000
tenants/dev-john/values.yaml (Layer 3, Developer Override):textglobal:
  namespace: ns-dev-john
services:  # Selective override for UI only (#18)
  ui:
    chartVersion: chart-pr-123-john
    image:
      tag: pr-123-john
    microservice:
      env:
        DEBUG_LEVEL: high
# Billing inherits from env-types/dev
tenants/customer1-prod/values.yaml (Layer 3, Customer Override):textglobal:
  namespace: ns-customer1-prod
services:  # Minimal tweak for UI
  ui:
    ingress:
      domain: prod.example.com/customer1

Step 4: Service Repos (UI-repo and Billing-repo)
Each has a Helm chart (#11-12).

UI-repo/charts/ui/Chart.yaml: apiVersion: v2, name: ui, version: 1.0.0
UI-repo/charts/ui/values.yaml: Defaults for microservice/Ingress.
UI-repo/charts/ui/templates/deployment.yaml: {{- if .Values.microservice.enabled }} Deployment for UI... {{- end }}
Similar for Billing-repo: Add FlinkJob template in templates/.

Step 5: ArgoCD Configs

argocd/appprojects.yaml (Isolation via RBAC #3):textapiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: dev
spec:
  destinations: [{namespace: 'ns-dev-*', server: '*'}]
  sourceRepos: ['*']
# Repeat for qa, staging, prod
argocd/applicationset.yaml (One App per tenant #21-22, auto-onboarding #25):textapiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: tenants
spec:
  generators:
  - git:
      repoURL: https://github.com/org/cluster-01-tenants.git
      revision: main
      directories:
      - path: tenants/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: '{{path.basename | splitList "-" | last }}'
      sources:
      - repoURL: https://github.com/org/ui-repo.git
        targetRevision: '{{.services.ui.chartVersion}}'
        path: charts/ui
        helm:
          valueFiles:
          - ../../bases/values.yaml
          - '../../env-types/{{path.basename | splitList "-" | last }}/values.yaml'
          - '{{path}}/values.yaml'
      - repoURL: https://github.com/org/billing-repo.git
        targetRevision: '{{.services.billing.chartVersion}}'
        path: charts/billing
        helm:
          valueFiles: [...]  # Same as above
      destination:
        namespace: 'ns-{{path.basename}}'
        server: https://kubernetes.default.svc
      syncPolicy:
        automated: { prune: true, selfHeal: true }

Step 6: CI Workflows (GitHub Actions)
Place in .github/workflows/ of respective repos.

PR Validation (in ui-repo, #16):textname: PR Validation
on: pull_request
jobs:
  test-isolated:
    steps:
    - checkout@v4
    - run: |  # Build temp image/chart, tag pr-<number>-<actor>
    - uses: github-script@v6  # Bot commit to tenants/dev-<actor>/values.yaml (update services.ui section)
    # ArgoCD auto-syncs—no direct deploy
Merge to Dev (in ui-repo, #17):textname: Merge to Dev
on: push: branches: [main]
jobs:
  promote-dev:
    steps:
    - checkout@v4
    - run: |  # Release stable tag
    - uses: github-script@v6  # Update env-types/dev/values.yaml (services.ui section)
    # ArgoCD cascades to all dev tenants
Promotion (in cluster-01-tenants, #7-10):textname: Promote
on: workflow_dispatch
inputs: fromEnv, toEnv
jobs:
  promote:
    steps:
    - checkout@v4
    - run: cp env-types/$$ {{ inputs.fromEnv }}/values.yaml env-types/ $${{ inputs.toEnv }}/values.yaml
    - uses: manual-approval@v1  # Gate
    - run: git commit -m "Promote ${{ inputs.fromEnv }} to ${{ inputs.toEnv }}" && git push
    # ArgoCD syncs to toEnv tenants

Step 7: POC Demo Steps

Bootstrap: Deploy ArgoCD, apply appprojects.yaml and applicationset.yaml (ArgoCD self-manages).
Add Tenant: Create tenants/customer2-qa/values.yaml, commit/push—ArgoCD auto-creates App and deploys.
PR Test: In ui-repo, open PR—CI commits override, ArgoCD syncs to ns-dev-john.
Merge: Merge PR—CI updates env-types/dev/values.yaml, ArgoCD cascades.
Promote: Dispatch promote.yaml (dev to qa)—approve, commit, ArgoCD syncs qa tenants.
Rollback: Update values.yaml to old tag, commit—ArgoCD resyncs.
Verify: In ArgoCD UI, check Apps (one per tenant), sync status, and resources (UI/Billing unified).

This POC proves the concept: Run on Minikube, scale to real cluster by updating destinations. If issues, debug via ArgoCD UI/logs. Let me know for refinements!