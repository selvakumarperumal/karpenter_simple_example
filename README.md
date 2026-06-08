# AWS EKS + Karpenter + ArgoCD — Production DevOps Workflow

A complete, production-grade reference showing how experienced AWS platform
engineers divide responsibilities between **Terraform**, **Helm**, **Karpenter**,
**ArgoCD**, and **CI/CD pipelines**.

## Deployment Model

```
Terraform (helm_release)          ArgoCD (App of Apps — sync waves)
─────────────────────────         ──────────────────────────────────────
ArgoCD     ← bootstrapper         Wave 0: cert-manager, external-secrets
                                  Wave 1: Karpenter Helm chart
                                  Wave 2: Karpenter manifests (NodePool, EC2NodeClass)
                                  Wave 3: ingress-nginx, prometheus
                                  Wave 4: fastapi app
                                  ...more apps
```

**Single command to bring up the entire stack:**
```bash
terraform apply -var='git_repository_url=https://github.com/YOUR_ORG/karpenter-demo.git'
```

After that, everything is driven by Git → ArgoCD. No bootstrap scripts needed.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Responsibility Matrix — What Goes Where](#2-responsibility-matrix)
3. [The Complete Step-by-Step Workflow](#3-complete-workflow)
4. [Service Account Management (IRSA vs Pod Identity)](#4-service-account-management)
5. [GitOps and CI/CD Flow](#5-gitops-and-cicd-flow)
6. [Repository Structure](#6-repository-structure)
7. [Running This Example](#7-running-this-example)
8. [Key Concepts FAQ](#8-key-concepts-faq)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AWS Account                                  │
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  VPC (10.0.0.0/16)                                           │   │
│  │                                                              │   │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │   │
│  │  │ Private AZ-a│  │ Private AZ-b│  │ Private AZ-c│         │   │
│  │  │  10.0.1.0   │  │  10.0.2.0   │  │  10.0.3.0   │         │   │
│  │  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘         │   │
│  │         │                │                │                  │   │
│  │  ┌──────▼──────────────────────────────────▼──────────────┐ │   │
│  │  │              EKS Cluster (v1.32)                        │ │   │
│  │  │                                                         │ │   │
│  │  │  ┌─────────────────────────────────────────────────┐   │ │   │
│  │  │  │  System Node Group (m5.large × 2)               │   │ │   │
│  │  │  │  Taint: CriticalAddonsOnly=true:NoSchedule      │   │ │   │
│  │  │  │                                                  │   │ │   │
│  │  │  │  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │   │ │   │
│  │  │  │  │Karpenter │  │  ArgoCD  │  │  CoreDNS /   │  │   │ │   │
│  │  │  │  │controller│  │  server  │  │  kube-proxy  │  │   │ │   │
│  │  │  │  └──────────┘  └──────────┘  └──────────────┘  │   │ │   │
│  │  │  └─────────────────────────────────────────────────┘   │ │   │
│  │  │                         │                               │ │   │
│  │  │         Karpenter sees unschedulable pods               │ │   │
│  │  │                         │                               │ │   │
│  │  │  ┌──────────────────────▼──────────────────────────┐   │ │   │
│  │  │  │  Karpenter-managed Nodes (auto-provisioned)      │   │ │   │
│  │  │  │                                                  │   │ │   │
│  │  │  │  ┌────────────┐  ┌────────────┐  ┌──────────┐  │   │ │   │
│  │  │  │  │ fastapi    │  │ fastapi    │  │  ...more │  │   │ │   │
│  │  │  │  │ pod (AZ-a) │  │ pod (AZ-b) │  │  apps    │  │   │ │   │
│  │  │  │  └────────────┘  └────────────┘  └──────────┘  │   │ │   │
│  │  │  └─────────────────────────────────────────────────┘   │ │   │
│  │  └─────────────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  IAM Roles:  [Karpenter Controller Role]  [Karpenter Node Role]     │
│  ECR:        [fastapi-app repository]                               │
│  SSM:        [/karpenter-demo/karpenter/node-role-name]             │
└─────────────────────────────────────────────────────────────────────┘
```

### Key insight: Two-layer node design

| Layer | Who manages it | Purpose |
|---|---|---|
| **System Node Group** | Terraform (fixed, always-on) | Runs Karpenter, ArgoCD, CoreDNS |
| **Application Nodes** | Karpenter (dynamic, auto-scaled) | Runs your apps |

The system node group has a `CriticalAddonsOnly=true:NoSchedule` taint.
Application pods do **not** tolerate this taint, so they cannot land on system
nodes. Karpenter sees those unschedulable pods and provisions fresh EC2
instances in seconds.

---

## 2. Responsibility Matrix

This is the most important table for understanding the architecture.

| Resource | Tool | Reason |
|---|---|---|
| VPC / Subnets / NAT | **Terraform** | Foundational AWS infrastructure |
| EKS Cluster | **Terraform** | Foundational AWS infrastructure |
| OIDC Provider | **Terraform** | Created automatically by the EKS module |
| EKS Managed Add-ons (CoreDNS, VPC-CNI) | **Terraform** | Tied to cluster lifecycle |
| System Node Group | **Terraform** | Needed before any pod can run |
| IAM Roles (Karpenter controller) | **Terraform** | AWS resource; needs least-privilege policy |
| IAM Roles (Karpenter node) | **Terraform** | AWS resource; attached to EC2 instances |
| Pod Identity Association | **Terraform** | Links K8s ServiceAccount → IAM Role in AWS |
| SSM Parameter (node role name) | **Terraform** | Bridge between Terraform outputs and K8s manifests |
| ECR Repository | **Terraform** | AWS resource |
| **ArgoCD install** | **Terraform** `helm_release` | Bootstrapper — must exist before GitOps can work |
| **Karpenter install** | **ArgoCD** (sync wave 1) | Installed by ArgoCD on system nodes |
| **NodePool** | **ArgoCD** (sync wave 2) | K8s CRD, applied via Kustomize (k8s/karpenter-config/) |
| **EC2NodeClass** | **ArgoCD** PostSync Job | Needs dynamic IAM role from SSM → Secret → Job |
| **Karpenter ServiceAccount** | **Terraform** | Bootstrap dependency before ArgoCD runs
| **Application Deployments** | **ArgoCD** (GitOps) | Dev team commits manifest → ArgoCD deploys |
| **Services / Ingress** | **ArgoCD** (GitOps) | Same as above |
| **Namespaces** | **ArgoCD** (GitOps) | `CreateNamespace=true` in ArgoCD sync options |

### The golden rule

```
Terraform  →  AWS resources (IAM, VPC, EKS, ECR, SSM)
ArgoCD     →  Cluster-level tools (Karpenter, cert-manager, Prometheus)
ArgoCD     →  Application workloads (Deployments, Services, Ingress)
CI/CD      →  Image build + manifest tag update (triggers ArgoCD)
```

---

## 3. Complete Workflow

### Phase 1 — Terraform (Platform Engineer, run once)

```
terraform apply
    │
    ├── VPC + Subnets + NAT Gateway
    ├── EKS Cluster + OIDC Provider + EKS Add-ons
    ├── System Node Group  (m5.large × 2, tainted — runs ArgoCD + Karpenter)
    ├── Karpenter IAM Role + Pod Identity Association
    ├── Karpenter Node IAM Role + Instance Profile
    ├── SSM Parameter (node role name for ESO to read)
    ├── ESO IAM Role + Kubernetes ServiceAccount (IRSA)
    │
    ├── helm_release "argocd"             ← installs ArgoCD on system nodes
    │
    └── null_resource "app_of_apps"       ← kubectl applies ONE Application object
                                              pointing ArgoCD at k8s/argocd/apps/
```

### Phase 2 — ArgoCD takes over (fully automated, sync waves)

```
ArgoCD reads k8s/argocd/apps/ from Git
    │
    ├── Wave 0: cert-manager.yaml        → helm install cert-manager v1.17.1
    ├── Wave 0: external-secrets.yaml    → helm install external-secrets v0.12.1
    ├── Wave 1: karpenter.yaml           → helm install karpenter v1.1.1
    ├── Wave 2: karpenter-config.yaml    → kustomize apply k8s/karpenter-config/
    │     ├── ClusterSecretStore + ExternalSecret → K8s Secret with node role
    │     ├── NodePool (static)
    │     └── PostSync Job → applies EC2NodeClass with real role name
    ├── Wave 3: ingress-nginx.yaml       → helm install ingress-nginx v4.12.0
    ├── Wave 3: prometheus.yaml          → helm install kube-prometheus-stack v72.4.0
    └── Wave 4: fastapi.yaml             → kubectl apply k8s/fastapi/
```

### Phase 3 — Developer workflow (every code change)

```
Developer pushes code
    │
    ▼
GitHub Actions
    ├── docker build ./app
    ├── docker push → ECR  (tag = git SHA)
    └── updates image tag in k8s/fastapi/deployment.yaml → git push
    │
    ▼
ArgoCD detects diff → rolls out new FastAPI pods
                    → Karpenter provisions nodes if needed
```

---

## 4. Service Account Management

### Which approach should you use in 2025–2026?

**EKS Pod Identity** — Use this for all new workloads.

| Feature | IRSA (older) | Pod Identity (recommended) |
|---|---|---|
| Setup | Annotate ServiceAccount with IAM Role ARN | Create Pod Identity Association in AWS |
| ServiceAccount annotation required | Yes | **No** |
| OIDC provider required | Yes | No |
| Works across accounts | Yes (with condition) | Yes |
| Supports session tags | No | **Yes** |
| Simpler Terraform | No | **Yes** |
| AWS support statement | Supported | **Recommended** |

#### How Pod Identity works (step by step)

```
1. Terraform creates IAM Role (karpenter-controller-role)
2. Terraform creates Pod Identity Association:
       (namespace=kube-system, serviceaccount=karpenter) → IAM Role ARN
3. Terraform creates ServiceAccount "karpenter" in kube-system
4. ArgoCD installs Karpenter Helm chart (reusing the existing ServiceAccount)
5. Karpenter pod requests AWS credentials → Agent returns STS tokens for the
   linked IAM Role → No annotation needed on the ServiceAccount
```

#### IRSA (if you need to stay with it)

```hcl
# In terraform/iam-karpenter.tf, swap these comments:

# enable_pod_identity             = true     ← comment out
# create_pod_identity_association = true     ← comment out

enable_irsa                      = true      # ← uncomment
irsa_oidc_provider_arn           = module.eks.oidc_provider_arn
irsa_namespace_service_accounts  = ["kube-system:karpenter"]
```

Then in Helm values, annotate the ServiceAccount:
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "<karpenter_iam_role_arn from terraform output>"
```

---

## 5. GitOps and CI/CD Flow

### What installs what — the definitive answer

```
                  Fresh AWS Account
                        │
              ┌─────────▼──────────┐
              │   terraform apply   │  ← ONE command
              └─────────┬──────────┘
                        │
               ┌────────┴──────────────────┐
               │                           │
     IAM roles, VPC, EKS         helm_release "argocd"
     SSM parameter, ESO SA       null_resource (App of Apps)
                                           │
                                     ArgoCD running
                                     Watching k8s/argocd/apps/
                                           │
        ┌──────────┬──────────┬────────────┼──────────┬──────────┐
        ▼          ▼          ▼            ▼          ▼          ▼
  cert-manager  ext-secrets  karpenter  karpenter  prometheus  fastapi
  (helm w0)     (helm w0)    (helm w1)  manifests  (helm w3)   (k8s w4)
                                        (kust w2)
```

| Component | Installed by | Managed by |
|---|---|---|
| ArgoCD | **Terraform** `helm_release` | Platform team — bump version in `helm-argocd.tf` |
| Karpenter | **ArgoCD** (sync wave 1) | Platform team — bump version in `k8s/argocd/apps/karpenter.yaml` |
| NodePool / EC2NodeClass | **ArgoCD** (sync wave 2) | Platform team — edit YAML, push to Git |
| cert-manager | **ArgoCD** (sync wave 0) | Platform team — edit `k8s/argocd/apps/cert-manager.yaml` |
| external-secrets | **ArgoCD** (sync wave 0) | Platform team — edit `k8s/argocd/apps/external-secrets.yaml` |
| ingress-nginx | **ArgoCD** (sync wave 3) | Platform team — edit `k8s/argocd/apps/ingress-nginx.yaml` |
| Prometheus | **ArgoCD** (sync wave 3) | Platform team — edit `k8s/argocd/apps/prometheus.yaml` |
| FastAPI app | **ArgoCD** (sync wave 4) | Dev team — edit `k8s/fastapi/` |

### Why ArgoCD installs Karpenter (not Terraform)

ArgoCD runs on the **system node group** — fixed, always-on nodes that exist
before Karpenter. There is no chicken-and-egg problem:

1. Terraform creates EKS + system nodes + ArgoCD
2. ArgoCD starts on system nodes (they tolerate the CriticalAddonsOnly taint)
3. ArgoCD installs Karpenter (sync wave 1)
4. ArgoCD applies NodePool + EC2NodeClass (sync wave 2)
5. Application pods trigger Karpenter → new nodes provisioned in ~60 seconds

### EC2NodeClass dynamic role injection

The EC2NodeClass needs the IAM role name (a Terraform output). Since ArgoCD
applies manifests from Git (not Terraform), we bridge the gap:

```
Terraform                    Kubernetes
─────────                    ──────────
module.karpenter             ExternalSecret
  → node_iam_role_name         → reads SSM parameter
  → aws_ssm_parameter           → creates K8s Secret
                                   "karpenter-node-config"
                                     → PostSync Job reads Secret
                                       → kubectl apply EC2NodeClass
                                         with real role name
```

---

## 6. Repository Structure

```
karpenter_simple_example/
│
├── app/                              ← FastAPI application code
│   ├── main.py                       Hello World API with pod/node info
│   ├── requirements.txt              Python dependencies (FastAPI, Uvicorn)
│   └── Dockerfile                    Multi-stage build, non-root user
│
├── terraform/                        ← AWS infra + ArgoCD bootstrap (platform team)
│   ├── providers.tf                  AWS (v6+), Kubernetes, Helm — exec-based auth
│   ├── variables.tf                  Input variables (region, cluster, K8s v1.32)
│   ├── main.tf                       Locals and data sources
│   ├── vpc.tf                        VPC, 3 private + 3 public subnets, NAT gateway
│   ├── eks.tf                        EKS cluster, add-ons, system node group (tainted)
│   ├── iam-karpenter.tf              Karpenter IAM (Pod Identity) + ESO IAM (IRSA) + SSM
│   ├── helm-karpenter.tf             Documentation only — Karpenter managed by ArgoCD
│   ├── helm-argocd.tf                helm_release ArgoCD + App of Apps bootstrap
│   └── outputs.tf                    Cluster endpoint, IAM ARNs, kubectl command
│
├── k8s/                              ← Kubernetes manifests (Git is source of truth)
│   │
│   ├── karpenter-config/             ← Applied by ArgoCD (karpenter-config, wave 2)
│   │   ├── kustomization.yaml        Resource list for Kustomize
│   │   ├── cluster-secret-store.yaml  ClusterSecretStore → ESO reads AWS SSM
│   │   ├── external-secret.yaml       ExternalSecret → K8s Secret with node role
│   │   ├── bootstrap-rbac.yaml        SA + ClusterRole for PostSync Job
│   │   ├── nodepool.yaml              NodePool — scheduling rules (static)
│   │   ├── bootstrap-job.yaml         PostSync Job — applies EC2NodeClass (dynamic)
│   │   └── ec2nodeclass.yaml          REFERENCE TEMPLATE (not applied directly)
│   │
│   ├── argocd/
│   │   ├── app-of-apps.yaml           Root Application (applied by Terraform)
│   │   └── apps/                      Child Application manifests
│   │       ├── cert-manager.yaml      Helm v1.17.1 (wave 0)
│   │       ├── external-secrets.yaml  Helm v0.12.1 (wave 0)
│   │       ├── karpenter.yaml         OCI Helm v1.1.1 (wave 1)
│   │       ├── karpenter-config.yaml  Kustomize (wave 2)
│   │       ├── ingress-nginx.yaml     Helm v4.12.0 (wave 3)
│   │       ├── prometheus.yaml        Helm v72.4.0 (wave 3)
│   │       └── fastapi.yaml           Plain manifests (wave 4)
│   │
│   └── fastapi/                      ← Dev team owns this; ArgoCD deploys it
│       ├── namespace.yaml             Dedicated namespace
│       ├── deployment.yaml            2 replicas, health checks, topology spread
│       ├── service.yaml               ClusterIP → port 80 → 8000
│       └── ingress.yaml               NGINX Ingress with ingressClassName
│
└── .github/
    └── workflows/
        └── app-ci.yaml               Build → Push ECR → Update manifest tag
```

---

## 7. Running This Example

### Prerequisites

```bash
# macOS
brew install awscli terraform kubectl

# Verify
aws --version          # >= 2.x
terraform --version    # >= 1.8
kubectl version --client # >= 1.30
```

### One command

```bash
cd terraform
terraform init
terraform apply \
  -var='git_repository_url=https://github.com/YOUR_ORG/karpenter-demo.git'
```

Terraform will, in order:
1. Create VPC, EKS, IAM (~15 min)
2. `helm install argocd`
3. Apply the App of Apps — ArgoCD then installs everything else automatically:
   - cert-manager + external-secrets (wave 0)
   - Karpenter Helm chart (wave 1)
     • Configured via NodePool + EC2NodeClass (see k8s/karpenter-config/)
   - ingress-nginx + Prometheus (wave 3)
   - FastAPI app (wave 4)

**That's it. No bootstrap scripts. No manual `kubectl apply` steps.**

### Verify

```bash
# Configure kubectl
aws eks update-kubeconfig --name karpenter-demo --region us-east-1

# Karpenter running on system nodes
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter

# ArgoCD running on system nodes
kubectl get pods -n argocd

# All child apps being synced
kubectl get applications -n argocd

# Once FastAPI pods are created, Karpenter provisions an application node
kubectl get nodes -w
kubectl get pods -n fastapi -w
```

### Access ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080  — user: admin
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

### Access Grafana UI

```bash
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80
# http://localhost:3000  — user: admin, password: changeme
```

### Adding a new tool (e.g. Istio)

1. Create `k8s/argocd/apps/istio.yaml` with the ArgoCD Application manifest
2. `git commit && git push`
3. ArgoCD detects the new file and installs Istio automatically

No Terraform changes. No `helm install`. Just Git.

---

## 8. Key Concepts FAQ

### Q: Why does ArgoCD install Karpenter instead of Terraform?

The system node group provides always-on nodes for ArgoCD. Once ArgoCD is
running, it can install Karpenter as just another Application — keeping the
entire cluster configuration in Git (GitOps). Sync waves ensure correct
ordering: ESO (wave 0) → Karpenter chart (wave 1) → NodePool/EC2NodeClass
(wave 2).

### Q: How does EC2NodeClass get the IAM role name?

```
Terraform  →  SSM Parameter  →  ExternalSecret  →  K8s Secret  →  PostSync Job  →  EC2NodeClass
```

The PostSync Job reads the Secret and `kubectl apply`s the EC2NodeClass with
the real role name substituted at runtime.

### Q: Why does Karpenter need a "system" node group at all?

Karpenter is itself a pod. It needs somewhere to run before it can provision
nodes. The system node group is that "somewhere". It runs with a fixed size
(2 nodes) and is never scaled by Karpenter. All application pods are managed
by Karpenter.

### Q: What is the difference between a NodePool and the old Cluster Autoscaler?

| Feature | Cluster Autoscaler | Karpenter |
|---|---|---|
| Scaling unit | ASG (node group) | Individual EC2 instance |
| Speed | 3–10 minutes | ~30–60 seconds |
| Instance flexibility | Fixed per node group | Any instance matching constraints |
| Spot support | Manual separate ASGs | Built-in, automatic fallback |
| Bin packing | No | Yes — consolidates underused nodes |
| AWS-native | No | Yes (v1 API since Aug 2024) |
| Disruption budgets | No | Yes (per-reason since v1.1) |

### Q: What about ingress-nginx being EOL?

The community `kubernetes/ingress-nginx` reached End-of-Life in March 2026.
This repo pins the final release (v4.12.0) for existing deployments.
Migration options:

- **F5 NGINX Ingress Controller** (`nginx/kubernetes-ingress`) — actively maintained
- **Kubernetes Gateway API** — the future standard
- **AWS Load Balancer Controller** — native AWS ALB/NLB management

### Q: Is this pattern actually used in production?

Yes. This is the **most common pattern** at companies running Kubernetes on AWS
as of 2025–2026. You will see minor variations:

- Some teams manage Karpenter via Terraform `helm_release` instead of ArgoCD
- Some teams use Flux instead of ArgoCD (same concept, different tool)
- Some teams use Atlantis or Spacelift for Terraform CI/CD

The core principle is always the same: **Terraform for AWS, GitOps for
everything in the cluster.**

### Q: How do I update Karpenter?

Edit the `targetRevision` in `k8s/argocd/apps/karpenter.yaml`:

```yaml
source:
  targetRevision: "1.1.1"  # ← update this
```

Push to Git. ArgoCD will upgrade Karpenter automatically. Always check the
[Karpenter upgrade guide](https://karpenter.sh/docs/upgrading/) before
bumping minor versions.

### Q: How do I restrict which apps ArgoCD can deploy?

Use **ArgoCD Projects**. By default everything goes into `project: default`
which has no restrictions. In production, create projects:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-backend
  namespace: argocd
spec:
  sourceRepos:
    - https://github.com/YOUR_ORG/karpenter-demo.git
  destinations:
    - namespace: fastapi
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
```

---

## Component Versions

| Component | Version | Notes |
|---|---|---|
| EKS Kubernetes | 1.32 | Latest stable |
| Terraform AWS Provider | ~> 6.0 | Required for EKS module v21+ |
| EKS Module | ~> 21.23.0 | terraform-aws-modules/eks/aws |
| VPC Module | ~> 6.6.1 | terraform-aws-modules/vpc/aws |
| ArgoCD Chart | 9.5.20 | Bootstrap only — self-managed after |
| Karpenter Chart | 1.12.1 | Stable v1 API |
| cert-manager | v1.20.2 | TLS certificate management |
| external-secrets | 2.6.0 | AWS SSM → K8s Secret sync |
| ingress-nginx | 4.15.1 | ⚠️ EOL — plan migration |
| kube-prometheus-stack | 86.2.0 | Prometheus + Grafana + Alertmanager |

---

## Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                   Who owns what?                                 │
├──────────────────────┬──────────────────────────────────────────┤
│ Platform Engineers   │ Terraform (VPC, EKS, IAM, ArgoCD)        │
│                      │ Run once per cluster                     │
├──────────────────────┼──────────────────────────────────────────┤
│ Platform Team GitOps │ ArgoCD Applications for cluster tooling  │
│                      │ (Karpenter, ingress, cert-manager,       │
│                      │  monitoring, external-secrets)           │
├──────────────────────┼──────────────────────────────────────────┤
│ Application Teams    │ k8s/fastapi/ manifests                   │
│                      │ Never touch Terraform or Helm            │
├──────────────────────┼──────────────────────────────────────────┤
│ CI/CD Pipeline       │ Build image → update manifest tag        │
│                      │ Does NOT run kubectl or terraform        │
└──────────────────────┴──────────────────────────────────────────┘
```
