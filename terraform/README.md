# Terraform Infrastructure Provisioning

This folder owns the AWS infrastructure configuration files. It uses Terraform to provision EKS, VPC networking, ECR registries, Secrets Manager placeholders, and all IAM role associations.

## Architecture

```
+-------------------------------------------------------------+
|                      terraform/ Folder                      |
|                                                             |
|   +--------------+                 +---------------+        |
|   |    vpc.tf    | --------------> |    eks.tf     |        |
|   +--------------+                 +---------------+        |
|          |                                 |                |
|          v                                 v                |
|   +--------------+                 +---------------+        |
|   |    ecr.tf    |                 |  iam-karpenter|        |
|   +--------------+                 +---------------+        |
+-------------------------------------------------------------+
```

| HCL File | Core Resource | Upstream Dependency | Downstream Target |
|:---|:---|:---|:---|
| `providers.tf` | Provider config | local binaries | AWS auth session |
| `variables.tf` | input variables | None | variables references |
| `main.tf` | Locals & AZs | AWS API | common tags |
| `vpc.tf` | `module "vpc"` | AWS Region | Subnet resources |
| `eks.tf` | `module "eks"` | `module.vpc` | cluster endpoint |
| `iam-karpenter.tf` | `module "karpenter"` | `module.eks` | Node IAM Role |
| `iam-external-secrets.tf` | secrets IAM role | `module.eks` | ESO ServiceAccount |
| `secrets.tf` | secrets placeholders | None | Secrets Manager path |
| `ecr.tf` | ECR repository | None | Container registry |
| `helm-argocd.tf` | `helm_release` | `module.eks` | ArgoCD controller |
| `outputs.tf` | Outputs mapping | All resources | outputs strings |

## File-by-file explanation

### providers.tf

The providers configuration file sets up AWS, Kubernetes, and Helm provider engines.

Here is the annotated version of `providers.tf` showing detailed comments:

```hcl
# The terraform block configures global settings including required version and provider constraints.
terraform {
  # Pins the minimum required Terraform engine version.
  required_version = ">= 1.8"

  # Lists the providers and their respective registry source paths and version constraints.
  required_providers {
    # AWS provider used for cloud resource management.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Kubernetes provider used to manage resources in EKS.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.1.0"
    }
    # Helm provider used to install Kubernetes charts.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2.0"
    }
  }

}

# Configures the AWS provider instance.
provider "aws" {
  # Target region where resources will be provisioned.
  region = var.aws_region
}

# Configures the Kubernetes provider.
provider "kubernetes" {
  # Targets the cluster endpoint exposed by EKS.
  host                   = module.eks.cluster_endpoint
  # Passes the cluster CA certificate for secure handshake.
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  # Configures authentication token execution.
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # Runs EKS get-token command to obtain short-lived credentials.
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

# Configures the Helm provider using the same authentication token mapping.
provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}
```

### main.tf

The main initialization file declares locals, tags, and data sources.

Here is the annotated version of `main.tf` showing detailed comments:

```hcl
# Binds local variables used throughout the configurations.
locals {
  # Binds cluster name local.
  cluster_name = var.cluster_name

  # Shared tags applied to all AWS resources.
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "karpenter-demo"
    Cluster     = var.cluster_name
  }
}

# Discovers available AWS availability zones in the configured region.
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Discovers current AWS account ID caller identity context.
data "aws_caller_identity" "current" {}
```

### variables.tf

The variables declaration file maps input variables to types and default configurations.

Here is the annotated version of `variables.tf` showing detailed comments:

```hcl
# Defines the AWS region hosting all infrastructure resources.
variable "aws_region" {
  description = "AWS region to deploy all resources into (VPC, EKS, IAM, etc.)"
  type        = string
  default     = "ap-south-1"
}

# Defines EKS cluster name used for SSM paths and tag discoveries.
variable "cluster_name" {
  description = "EKS cluster name — also used for Karpenter discovery tags and SSM parameter paths"
  type        = string
  default     = "karpenter-demo"
}

# Defines the Kubernetes control plane version.
variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster (must be supported by EKS)"
  type        = string
  default     = "1.33"
}

# Environment tag applied across resources.
variable "environment" {
  description = "Environment tag applied to all resources (e.g. production, staging, dev)"
  type        = string
  default     = "production"
}

# Git repository URL that ArgoCD watches.
variable "git_repository_url" {
  description = "Git repository URL that ArgoCD will watch for Kubernetes manifests"
  type        = string
  default     = "https://github.com/selvakumarperumal/karpenter_simple_example.git"
}
```

### outputs.tf

The outputs definition exposes endpoints and connection commands.

Here is the annotated version of `outputs.tf` showing detailed comments:

```hcl
# Exposes EKS cluster name.
output "cluster_name" {
  description = "EKS cluster name — used in kubectl config, Karpenter settings, and ArgoCD"
  value       = module.eks.cluster_name
}

# Exposes API server endpoint.
output "cluster_endpoint" {
  description = "Kubernetes API server endpoint URL"
  value       = module.eks.cluster_endpoint
}

# Exposes cluster CA data. Sensitive to prevent printing in stdout.
output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate (used by kubectl and CI/CD)"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

# Exposes convenience shell command to configure local kubectl context.
output "configure_kubectl" {
  description = "Run this command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

# Exposes Karpenter role ARN.
output "karpenter_iam_role_arn" {
  description = "IAM Role ARN for the Karpenter controller (injected via Pod Identity)"
  value       = module.karpenter.iam_role_arn
}

# Exposes node role name for Karpenter instances.
output "karpenter_node_iam_role_name" {
  description = "IAM Role name for Karpenter-provisioned EC2 nodes (used in EC2NodeClass.spec.role)"
  value       = module.karpenter.node_iam_role_name
}

# Exposes instance profile name.
output "karpenter_node_instance_profile_name" {
  description = "Instance Profile name attached to Karpenter-provisioned nodes"
  value       = module.karpenter.instance_profile_name
}

# Exposes VPC ID.
output "vpc_id" {
  description = "VPC ID where the EKS cluster and all nodes reside"
  value       = module.vpc.vpc_id
}

# Exposes private subnet IDs.
output "private_subnet_ids" {
  description = "Private subnet IDs — EKS nodes and Karpenter instances launch here"
  value       = module.vpc.private_subnets
}

# Exposes ECR repository URL.
output "ecr_repository_url" {
  description = "Full ECR repository URL for the FastAPI image (e.g. 123456789012.dkr.ecr.ap-south-1.amazonaws.com/fastapi-app)"
  value       = aws_ecr_repository.fastapi.repository_url
}

# Exposes ECR repository name.
output "ecr_repository_name" {
  description = "ECR repository name (used by CI pipeline to push images)"
  value       = aws_ecr_repository.fastapi.name
}
```

### vpc.tf

The VPC networking template creates subnets and NAT gateways.

Here is the annotated version of `vpc.tf` showing detailed comments:

```hcl
# Deploys the cluster VPC networking using the official modules.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6.1"

  # Name mapping for VPC resources.
  name = "${local.cluster_name}-vpc"
  # VPC IPv4 address scope.
  cidr = "10.0.0.0/16"

  # Limits public/private subnets to 3 AZs.
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # Provisions NAT Gateways to route private subnet traffic to the internet.
  enable_nat_gateway   = true
  # Uses single NAT gateway to minimize running costs.
  single_nat_gateway   = true
  # Enables hostnames required by EKS.
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags subnets to configure NLB creation.
  public_subnet_tags = {
    # Instructs Load Balancer Controller to create public internet-facing load balancers here.
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    # Instructs Load Balancer Controller to create private internal load balancers here.
    "kubernetes.io/role/internal-elb" = 1
    # Discovery tag matched by Karpenter EC2NodeClass subnet selectors.
    # Must match subnetSelectorTerms.tags in ec2nodeclass.yaml.
    "karpenter.sh/discovery" = local.cluster_name
  }

  tags = local.tags
}
```

### eks.tf

The EKS control plane template configures nodes and plugins.

Here is the annotated version of `eks.tf` showing detailed comments:

```hcl
# Deploys EKS cluster using EKS module.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.23.0"

  # Target cluster name.
  name               = local.cluster_name
  # EKS Kubernetes software version constraint.
  kubernetes_version = var.cluster_version

  # Exposes the Kubernetes API endpoint public and private paths.
  endpoint_public_access  = true
  endpoint_private_access = true

  # Binds the control plane network interfaces to VPC subnets.
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Grants administrator rights to the IAM role that runs this Terraform config.
  enable_cluster_creator_admin_permissions = true

  # Configures EKS Addon resources.
  addons = {
    # DNS services for pods.
    coredns = {
      most_recent = true
    }
    # Directs connection traffic.
    kube-proxy = {
      most_recent = true
    }
    # AWS VPC networking plugins.
    vpc-cni = {
      most_recent = true
    }
    # Agent managing EKS Pod Identity mapping.
    # Required by Karpenter controller to authenticate.
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  # Declares EKS-managed node groups.
  eks_managed_node_groups = {
    # System node group dedicated to controllers.
    system = {
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      labels = {
        role = "system"
      }

      # Taints system nodes to prevent scheduling application pods on them.
      taints = {
        system_only = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # Configures cluster node security group tags.
  node_security_group_tags = {
    # Discovery tag matched by Karpenter EC2NodeClass securityGroupSelectorTerms.
    # Must match securityGroupSelectorTerms.tags in ec2nodeclass.yaml.
    "karpenter.sh/discovery" = local.cluster_name
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.cluster_name
  })
}
```

### helm-argocd.tf

The ArgoCD helm release coordinates continuous delivery engines.

Here is the annotated version of `helm-argocd.tf` showing detailed comments:

```hcl
# Installs ArgoCD controller onto the cluster.
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.5.20"
  namespace  = "argocd"

  # Creates namespace if missing.
  create_namespace = true

  # Configuration overrides.
  set = [
    # Exposes the server internally.
    {
      name  = "server.service.type"
      value = "ClusterIP"
    },
    # Registers OCI ECR registry for Karpenter chart pulling.
    {
      name  = "configs.repositories.karpenter-oci.url"
      value = "oci://public.ecr.aws/karpenter"
    },
    {
      name  = "configs.repositories.karpenter-oci.name"
      value = "karpenter-oci"
    },
    {
      name  = "configs.repositories.karpenter-oci.type"
      value = "helm"
    },
    {
      name  = "configs.repositories.karpenter-oci.enableOCI"
      value = "true"
    }
  ]

  # Blocks CLI until resources are healthy.
  wait    = true
  timeout = 300

  # Requires active control plane.
  depends_on = [module.eks]
}
```

### helm-karpenter.tf

The Karpenter helm installation configuration file.

Here is the annotated version of `helm-karpenter.tf` showing detailed comments:

```hcl
# This file is intentionally left empty.
# Installing Karpenter via Terraform creates bootstrap dependency loops.
# Instead, Karpenter is deployed dynamically via ArgoCD sync configurations.
```

### iam-external-secrets.tf

The IAM mapping file provisions access for secrets synchronization.

Here is the annotated version of `iam-external-secrets.tf` showing detailed comments:

```hcl
# Creates IAM role for External Secrets operator.
resource "aws_iam_role" "external_secrets" {
  name = "external-secrets-${local.cluster_name}"

  # OIDC assume role trust policy context.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # Restricts role assumptions to the external-secrets ServiceAccount.
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.tags
}

# Defines permissions policy allowing read-only secrets management access.
resource "aws_iam_role_policy" "external_secrets_secretsmanager" {
  name = "secretsmanager-read-app-secrets"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      # Scopes access specifically to secrets under the cluster prefix name.
      # Must match secret name defined in secrets.tf.
      Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${local.cluster_name}/*"
    }]
  })
}

# Pre-creates the external-secrets namespace context.
resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
  }

  depends_on = [module.eks]
}

# ServiceAccount linking EKS to the AWS IAM external-secrets role via IRSA.
resource "kubernetes_service_account_v1" "external_secrets" {
  metadata {
    name      = "external-secrets"
    namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
    # Connects EKS ServiceAccount to AWS IAM Role.
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets.arn
    }
  }
}
```

### iam-karpenter.tf

The Karpenter controller IAM profiles coordination template.

Here is the annotated version of `iam-karpenter.tf` showing detailed comments:

```hcl
# Karpenter sub-module configuring IAM roles and instance profiles.
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.23.0"

  cluster_name = module.eks.cluster_name

  # Creates Pod Identity associations mapping controllers to IAM roles.
  create_pod_identity_association = true

  # Configures IAM role attached to EC2 nodes.
  create_node_iam_role = true
  node_iam_role_additional_policies = {
    # Allows EKS nodes to join cluster and connect via SSM.
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # Static node role naming, avoiding random strings.
  node_iam_role_use_name_prefix = false
  # Must match EC2NodeClass spec.role in ec2nodeclass.yaml.
  node_iam_role_name            = "karpenter-node-role"

  tags = local.tags
}
```

### secrets.tf

The Secrets Manager placeholder creation file.

Here is the annotated version of `secrets.tf` showing detailed comments:

```hcl
# Creates Google API Key secret metadata mapping placeholder in AWS Secrets Manager.
resource "aws_secretsmanager_secret" "google_api_key" {
  # Remote key path. Matches key lookup inside google-api-key.yaml.
  name        = "${local.cluster_name}/GOOGLE_API_KEY"
  description = "Google API Key for the FastAPI application"

  # Number of days before permanent deletion.
  recovery_window_in_days = 7

  tags = local.tags
}
```

### ecr.tf

The container image registry builder and lifecycle rule configuration template.

Here is the annotated version of `ecr.tf` showing detailed comments:

```hcl
# Provisions private ECR container registry repository.
resource "aws_ecr_repository" "fastapi" {
  # Registry repository name, matching ECR_REPOSITORY in app-ci.yaml.
  name                 = "fastapi-app"
  # Allows tagging container builds with identical version pointers.
  image_tag_mutability = "MUTABLE"
  # Enables cleanups during terraform destroy.
  force_delete         = true

  # Enables vulnerability scanning when images are uploaded.
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = local.tags
}

# ECR image lifecycle rules.
resource "aws_ecr_lifecycle_policy" "fastapi" {
  repository = aws_ecr_repository.fastapi.name

  # Expired image management parameters.
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images, expire older ones"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        # Restricts repository to keep only the 20 most recent image packages.
        countNumber = 20
      }
      action = {
        type = "expire"
      }
    }]
  })
}
```

## Versions and APIs used

| Component | target Version | Provider source |
|:---|:---|:---|
| Terraform Engine | `>= 1.8` | None |
| AWS Provider | `~> 6.0` | `hashicorp/aws` |
| Kubernetes Provider | `~> 3.1.0` | `hashicorp/kubernetes` |
| Helm Provider | `~> 3.2.0` | `hashicorp/helm` |

## Prerequisites

| Requirement | Target Configuration | Location |
|:---|:---|:---|
| AWS CLI | Active administrator permissions | local shell |

## Commands

We initialize Terraform plugins and upgrade providers.
```bash
terraform init
```

We check configurations changes against the AWS console.
```bash
terraform plan
```

We apply the configurations to provision AWS infrastructure.
```bash
terraform apply -var='git_repository_url=https://github.com/selvakumarperumal/karpenter_simple_example.git'
```

We remove all provisioned infrastructure.
```bash
terraform destroy
```

## Troubleshooting

We resolve module download issues by running `terraform init -upgrade` to clean local provider cache directories.

We resolve permissions issues by checking that your local AWS environment keys have administrator privileges.

## References

| Tool | Official Documentation |
|:---|:---|
| Terraform AWS Provider | [AWS Provider docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) |
| Terraform EKS Module | [EKS Module docs](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest) |
