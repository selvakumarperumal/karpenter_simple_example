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

The `terraform` block declares backend and required providers version requirements.
The `required_version = ">= 1.8"` argument sets the minimum version of Terraform. If run on older versions, initialization blocks.
The `aws` block sets source to `hashicorp/aws` and version to `~> 6.0`.
The `kubernetes` block configures kubernetes provider.
The `helm` block configures helm provider.

The `provider "aws"` block configures the AWS provider.
The `region` argument with value `var.aws_region` configures target region.

The `provider "kubernetes"` block configures authentication parameters.
The `host` argument points to EKS cluster API server (matches `cluster_endpoint` output).
The `cluster_ca_certificate` argument passes CA certificate.
The `exec` block configures short-lived token lookup.
The `api_version: "client.authentication.k8s.io/v1beta1"` parameter targets stable API schema.
The `command: "aws"` parameter calls AWS CLI.
The `args` parameter runs `eks get-token --cluster-name <name>` to fetch tokens. If wrong, provider calls fail to connect to EKS.

The `provider "helm"` block configures helm provider parameters using the same exec auth block.

### variables.tf

The `variable "aws_region"` block configures AWS region variable (default `"ap-south-1"`). Scopes all resources.

The `variable "cluster_name"` block configures EKS cluster name (default `"karpenter-demo"`). References Karpenter tags.

The `variable "cluster_version"` block configures Kubernetes version (default `"1.33"`).

The `variable "environment"` block configures environment tag.

The `variable "git_repository_url"` block configures Git repository target URL. Passed to ArgoCD.

### main.tf

The `locals` block defines shared properties.
The `cluster_name` local binds to cluster name variable.
The `tags` local maps tags applied to all resources.

The `data "aws_availability_zones" "available"` block discovers standard Availability Zones inside region.
The `filter` parameter with values `opt-in-not-required` filters out local zones.

The `data "aws_caller_identity" "current"` block fetches AWS account information.

### vpc.tf

The `module "vpc"` block deploys network resources.
The `source` parameter targets `terraform-aws-modules/vpc/aws`.
The `version` parameter pins the module to `~> 6.6.1`.
The `name` parameter sets VPC name.
The `cidr = "10.0.0.0/16"` argument sets VPC CIDR scope.
The `azs` parameter scopes subnets to first 3 AZs.
The `private_subnets` and `public_subnets` assign CIDRs per AZ.
The `enable_nat_gateway = true` and `single_nat_gateway = true` arguments configure NAT gateway resources. Uses single NAT gateway to control costs (production should configure this to false for HA).
The `enable_dns_hostnames = true` and `enable_dns_support = true` arguments are required by EKS to resolve cluster endpoints.
The `public_subnet_tags` and `private_subnet_tags` apply tags.
The `kubernetes.io/role/elb = 1` tag instructs load balancer controller to create public NLBs here.
The `kubernetes.io/role/internal-elb = 1` tag targets internal load balancers.
The `karpenter.sh/discovery = local.cluster_name` tag is critical; matches `subnetSelectorTerms` in [ec2nodeclass.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/karpenter-config/templates/ec2nodeclass.yaml#L49-L52). If wrong, Karpenter cannot provision nodes.

### eks.tf

The `module "eks"` block provisions the cluster.
The `source` parameter targets `terraform-aws-modules/eks/aws`.
The `version` parameter pins the module to `~> 21.23.0`.
The `name` parameter sets EKS cluster name.
The `kubernetes_version = var.cluster_version` argument targets EKS version.
The `endpoint_public_access = true` and `endpoint_private_access = true` fields configure endpoint visibility.
The `vpc_id` and `subnet_ids` place control plane interfaces inside VPC.
The `enable_cluster_creator_admin_permissions = true` argument grants administrator access to the IAM identity running Terraform.
The `addons` block installs `coredns`, `kube-proxy`, `vpc-cni`, and `eks-pod-identity-agent`. EKS Pod Identity Agent is required by Karpenter to assume IAM roles without SA annotations.
The `eks_managed_node_groups.system` block configures a tainted node group.
The `instance_types` parameter selects `m5.large`.
The `min_size = 2`, `max_size = 3`, and `desired_size = 2` fields set system group size boundaries.
The `taints` block configures `CriticalAddonsOnly=true:NoSchedule` taint, restricting the node group to run only system pods.
The `node_security_group_tags` tag `karpenter.sh/discovery = local.cluster_name` is critical; matches `securityGroupSelectorTerms` in [ec2nodeclass.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/karpenter-config/templates/ec2nodeclass.yaml#L54-L58).

### iam-karpenter.tf

The `module "karpenter"` block configures Karpenter controller IAM roles.
The `source` parameter targets `terraform-aws-modules/eks/aws//modules/karpenter`.
The `version` parameter pins the module to `~> 21.23.0`.
The `cluster_name` parameter binds to EKS.
The `create_pod_identity_association = true` argument binds EKS Pod Identity mapping.
The `create_node_iam_role = true` argument configures role creation.
The `node_iam_role_additional_policies` adds `AmazonSSMManagedInstanceCore` to enable SSM Session Manager access.
The `node_iam_role_use_name_prefix = false` and `node_iam_role_name = "karpenter-node-role"` configurations configure a static role name (matches `role` in [ec2nodeclass.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/karpenter-config/templates/ec2nodeclass.yaml#L46)). If wrong, node scaling fails.

### iam-external-secrets.tf

The `aws_iam_role.external_secrets` resource configures the IAM role for the secrets operator.
The `assume_role_policy` statement binds OIDC trust to the `external-secrets` ServiceAccount.

The `aws_iam_role_policy.external_secrets_secretsmanager` resource defines read rights.
The `Resource` argument scopes read rights specifically to path `arn:aws:secretsmanager:*:*:secret:${local.cluster_name}/*` only. If wrong, secrets Operator fails to read keys.

The `kubernetes_namespace_v1.external_secrets` resource pre-creates target namespace.

The `kubernetes_service_account_v1.external_secrets` resource configures the ServiceAccount annotated with EKS IRSA role mapping.

### secrets.tf

The `aws_secretsmanager_secret.google_api_key` resource creates a secret placeholder path (matches lookup name inside [google-api-key.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/secrets/templates/google-api-key.yaml#L30)).
The `recovery_window_in_days = 7` argument sets deletion grace period.

### ecr.tf

The `aws_ecr_repository.fastapi` resource creates private ECR registry name `"fastapi-app"` (matches repository targets inside [app-ci.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/.github/workflows/app-ci.yaml#L13)).
The `image_tag_mutability = "MUTABLE"` configuration allows tag overwrites.
The `force_delete = true` argument allows ECR deletion during terraform destroy runs.
The `scan_on_push = true` configuration enables security scans.

The `aws_ecr_lifecycle_policy.fastapi` resource configures image lifecycle rules.
The `policy` JSON statement configures keeping only the 20 most recent image tags.

### helm-argocd.tf

The `helm_release.argocd` resource installs the ArgoCD controller.
The `repository` parameter targets official chart registry.
The `chart` parameter targets `argo-cd`.
The `version` parameter pins the chart version to `9.5.20`.
The `create_namespace = true` argument creates namespace.
The `set` parameters register public OCI registry `oci://public.ecr.aws/karpenter` to allow image pulls.

### helm-karpenter.tf

Contains architectural notes documenting why Karpenter controller installation is delegated to ArgoCD GitOps syncs instead of Terraform.

### outputs.tf

Exposes key parameters (cluster API endpoint, ECR registry URL, and local kubectl configuration commands).

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
