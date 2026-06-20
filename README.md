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

## Deploy

We initialize the Terraform working directory to download all required providers and module sources.
```bash
terraform -chdir=terraform init
```

We apply the Terraform configuration to provision the VPC, EKS cluster, IAM roles, ECR repository, Secrets Manager entry, and the ArgoCD Helm installation. The `git_repository_url` variable tells ArgoCD which repository to watch.
```bash
terraform -chdir=terraform apply \
  -var='git_repository_url=https://github.com/selvakumarperumal/karpenter_simple_example.git'
```

We configure the local `kubectl` context so subsequent commands target the newly provisioned cluster. Terraform prints this exact command as the `configure_kubectl` output.
```bash
$(terraform -chdir=terraform output -raw configure_kubectl)
```

We export the three shell variables consumed by `envsubst`, then substitute them into `app-of-apps.yaml` and apply it to register the root ArgoCD Application that bootstraps all child applications.
```bash
export GIT_REPOSITORY_URL="https://github.com/selvakumarperumal/karpenter_simple_example.git"
export CLUSTER_NAME="karpenter-demo"
export AWS_REGION="ap-south-1"
envsubst < k8s/argocd/app-of-apps.yaml | kubectl apply -f -
```

We populate the Google API Key inside Secrets Manager so the External Secrets Operator can sync it into the `fastapi` namespace.
```bash
aws secretsmanager put-secret-value \
  --secret-id karpenter-demo/GOOGLE_API_KEY \
  --secret-string "my-secret-key-value"
```

We verify that all ArgoCD child applications have reached `Synced` and `Healthy` status before considering the deploy complete.
```bash
kubectl get applications -n argocd
```

## Destroy

We delete the root ArgoCD Application with foreground cascading so that ArgoCD removes every child Application in reverse sync-wave order and waits for each Kubernetes resource — pods, services, load balancers, and CRDs — to fully terminate before proceeding. Skipping this step leaves orphaned AWS load balancers that prevent VPC deletion.
```bash
kubectl delete application app-of-apps -n argocd \
  --cascade=foreground \
  --timeout=300s
```

We confirm that every application namespace has fully terminated before tearing down the cluster. Kubernetes must release all node-hosted resources first.
```bash
for NS in fastapi monitoring keda external-secrets cert-manager istio-system gateway-system; do
  kubectl wait --for=delete namespace/"$NS" --timeout=300s || true
done
```

We delete remaining Karpenter-provisioned nodes. These nodes are not tracked in the Terraform-managed node group and must be removed explicitly before `terraform destroy` can delete the EKS cluster cleanly.
```bash
kubectl delete nodeclaims --all --ignore-not-found=true
kubectl delete nodepools --all --ignore-not-found=true
kubectl delete ec2nodeclasses --all --ignore-not-found=true
kubectl delete nodes -l role=application --ignore-not-found=true
```

We run Terraform destroy to remove the EKS cluster, IAM roles, VPC, ECR repository, and Secrets Manager secret. All Kubernetes workloads must be cleared first using the ArgoCD steps above.
```bash
terraform -chdir=terraform destroy \
  -var='git_repository_url=https://github.com/selvakumarperumal/karpenter_simple_example.git'
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
