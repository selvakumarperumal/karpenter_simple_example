# Karpenter GitOps Reference Implementation

This repository owns the reference codebase to provision and manage a zone-aware FastAPI application inside Amazon EKS with dynamic auto-scaling driven by Karpenter and KEDA. It includes the Terraform modules to build the core AWS infrastructure and bootstrap ArgoCD, the application Docker context, and the Helm templates that ArgoCD monitors to reconcile cluster state.

## Architecture

```
+-------------------------------------------------------------+
|                      Project Layout                         |
|                                                             |
|   [terraform/] ---> [Bootstraps EKS & ArgoCD]               |
|                                |                            |
|                                v                            |
|                     [ArgoCD App of Apps]                    |
|                                |                            |
|                                v                            |
|    [k8s/] --------> [Syncs Workloads and Controllers]        |
|                                ^                            |
|                                |                            |
|   [.github/] -----> [Pushes container updates to ECR]       |
+-------------------------------------------------------------+
```

| Directory Path | Purpose |
|:---|:---|
| `app/` | Holds the FastAPI python application source code, requirements, and Dockerfile packaging script. |
| `terraform/` | Bootstraps AWS network configurations, IAM identities, EKS clusters, and the ArgoCD Helm installation. |
| `k8s/` | Holds Helm templates representing target workloads, namespaces, autoscalers, gateways, and provisioning rules. |
| `.github/` | Configures continuous integration pipelines to compile containers and update deployment tags. |

## File-by-file explanation

### app

The `app/` directory contains the FastAPI code and container packaging logic. If wrong, ECR registry images cannot be built or run.

### terraform

The `terraform/` directory contains HCL modules to provision AWS environments. If wrong, Kubernetes control planes or IAM mappings will not exist.

### k8s

The `k8s/` directory contains Helm charts representing target workload states. If wrong, ArgoCD cannot synchronize controllers or application gateways.

### .github

The `.github/` directory contains GitHub Actions workflow code. If wrong, automatic container compilation and registry pushes are disabled.

## Versions and APIs used

| Component | Target Version | apiVersion Group |
|:---|:---|:---|
| Terraform Engine | `>= 1.8` | None |
| Kubernetes (EKS) | `1.33+` | Standard groups |
| AWS Provider | `~> 6.0` | `hashicorp/aws` |
| Karpenter | v1.11+ | `karpenter.sh/v1` |
| KEDA | 2.20+ | `keda.sh/v1alpha1` |
| Istio | 1.29+ | `gateway.networking.k8s.io/v1` |
| FastAPI | 0.136+ | None |

## Prerequisites

| Requirement | Target Configuration | Location |
|:---|:---|:---|
| AWS CLI | Active administrator permissions | local shell |
| Terraform | `1.8+` engine installed | local shell |
| kubectl | CLI client installed | local shell |
| envsubst | Environment substitution CLI | local shell |

## Commands

We initialize and apply Terraform configurations inside the HCL directory to build VPC networking, EKS cluster nodes, IAM role configurations, and bootstrap ArgoCD.
```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply -var='git_repository_url=https://github.com/selvakumarperumal/karpenter_simple_example.git'
```

We configure local kubectl context using the output command string from Terraform.
```bash
$(terraform -chdir=terraform output -raw configure_kubectl)
```

We apply the root App-of-Apps manifest using envsubst to register parent resources in ArgoCD.
```bash
export GIT_REPOSITORY_URL="https://github.com/selvakumarperumal/karpenter_simple_example.git"
export CLUSTER_NAME="karpenter-demo"
export AWS_REGION="ap-south-1"
envsubst < k8s/argocd/app-of-apps.yaml | kubectl apply -f -
```

We upload the target secret to AWS Secrets Manager to configure application variables.
```bash
aws secretsmanager put-secret-value --secret-id karpenter-demo/GOOGLE_API_KEY --secret-string "my-secret-key-value"
```

## Troubleshooting

We resolve resource lookup failures during EKS provision runs by checking that the AWS CLI keys are valid and have not expired in AWS.

We resolve GitOps sync blocks by checking that the repository target parameters inside the applied manifests match your git repository.

We resolve node scaling blocks by checking that subnets inside AWS include matching tags for Karpenter auto-discovery.

## References

| Tool | Official Documentation |
|:---|:---|
| Terraform | [Terraform docs](https://www.terraform.io/docs) |
| Amazon EKS | [AWS EKS docs](https://docs.aws.amazon.com/eks/) |
| ArgoCD | [ArgoCD docs](https://argo-cd.readthedocs.io/en/stable/) |
| Karpenter | [Karpenter docs](https://karpenter.sh/docs/) |
