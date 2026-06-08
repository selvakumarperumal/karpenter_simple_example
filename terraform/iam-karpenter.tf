# ── Karpenter IAM ─────────────────────────────────────────────────────────────
#
# PURPOSE:
#   Creates all IAM resources required by the Karpenter autoscaler and the
#   External Secrets Operator (ESO). These are AWS-side resources that must
#   exist before any Kubernetes workload can use them.
#
# RESOURCES CREATED:
#   1. module.karpenter:
#      • Controller IAM Role — assumed by the Karpenter controller pod
#      • Pod Identity Association — maps (kube-system, karpenter) → IAM Role
#      • Node IAM Role — assumed by EC2 instances that Karpenter provisions
#      • Instance Profile — wraps the Node IAM Role for EC2 launch
#
#   2. aws_ssm_parameter:
#      • Stores the Node IAM Role name in SSM Parameter Store so it can be
#        read by External Secrets Operator without exposing Terraform outputs
#
#   3. aws_iam_role.external_secrets:
#      • IAM Role for ESO with IRSA trust policy
#      • Grants ssm:GetParameter on the Karpenter node role name parameter
#
#   4. kubernetes_service_account.external_secrets:
#      • Pre-creates the ESO ServiceAccount with the IRSA annotation
#      • The ESO Helm chart is told serviceAccount.create=false to reuse this
#
# DATA FLOW (Terraform → SSM → ESO → K8s Secret → EC2NodeClass):
#   Terraform creates IAM role → writes role name to SSM parameter
#   → ESO reads SSM → creates K8s Secret "karpenter-node-config"
#   → ArgoCD PostSync Job reads Secret → kubectl applies EC2NodeClass
#   → Karpenter uses the role when launching EC2 instances
#
# IDENTITY METHOD:
#   Karpenter uses EKS Pod Identity (recommended over IRSA for new clusters).
#   ESO uses IRSA because the Terraform-managed ServiceAccount annotation
#   provides a clean handoff between Terraform and the Helm chart.
# ─────────────────────────────────────────────────────────────────────────────
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.23.0"

  cluster_name = module.eks.cluster_name

  # ── EKS Pod Identity (recommended in 2025-2026) ──────────────────────────
  # Pod Identity is simpler than IRSA: no annotation needed on the
  # ServiceAccount — EKS automatically injects credentials based on the
  # (namespace, serviceaccount) → IAM role mapping stored in AWS.
  #
  # The eks-pod-identity-agent add-on (installed in eks.tf) runs as a
  # DaemonSet and intercepts credential requests from pods.
  create_pod_identity_association = true

  # ── Alternative: IRSA (older but widely used) ────────────────────────────
  # Uncomment these and comment the Pod Identity block above to use IRSA:
  # enable_irsa                      = true
  # irsa_oidc_provider_arn           = module.eks.oidc_provider_arn
  # irsa_namespace_service_accounts  = ["kube-system:karpenter"]

  # ── Node IAM Role ─────────────────────────────────────────────────────────
  # The EC2 instances launched by Karpenter need their own IAM role.
  # This role is referenced in EC2NodeClass.spec.role (see k8s/karpenter/).
  create_node_iam_role = true
  node_iam_role_additional_policies = {
    # Enables SSM Session Manager on Karpenter nodes (useful for debugging —
    # connect to nodes without SSH keys via `aws ssm start-session`)
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

# ── Kubernetes ServiceAccount for Karpenter (Terraform-managed) ───────────────
# Created here to satisfy the architectural requirement that bootstrap 
# ServiceAccounts are managed by Terraform before ArgoCD runs.
resource "kubernetes_service_account_v1" "karpenter" {
  metadata {
    name      = "karpenter"
    namespace = "kube-system"
  }
  depends_on = [module.eks]
}

# ── SSM Parameter — node IAM role name ────────────────────────────────────────
# Stores the Karpenter node IAM role name in AWS SSM Parameter Store.
#
# WHY SSM instead of a ConfigMap or direct Terraform output:
#   • The EC2NodeClass is applied by ArgoCD (not Terraform), so Terraform
#     outputs aren't directly accessible.
#   • SSM is the standard AWS secret/config store — External Secrets Operator
#     can read it natively without custom scripts.
#   • This decouples the Terraform apply from the K8s manifest lifecycle.
#
# CONSUMED BY:
#   k8s/karpenter/external-secret.yaml → reads this SSM parameter
#   → creates K8s Secret "karpenter-node-config" in kube-system
resource "aws_ssm_parameter" "karpenter_node_role_name" {
  name  = "/${local.cluster_name}/karpenter/node-role-name"
  type  = "String"
  value = module.karpenter.node_iam_role_name

  tags = local.tags
}

# ── IAM for External Secrets Operator (IRSA) ──────────────────────────────────
# WHY IRSA (not Pod Identity) for ESO:
#   The ESO ServiceAccount is created by Terraform (not the Helm chart) so we
#   can set the IRSA annotation alongside the IAM role in a single apply.
#   This ensures ESO can authenticate immediately when ArgoCD installs it.
#
# TRUST POLICY:
#   Only the "external-secrets" ServiceAccount in the "external-secrets"
#   namespace can assume this role, enforced via OIDC conditions.
resource "aws_iam_role" "external_secrets" {
  name = "external-secrets-${local.cluster_name}"

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
          "${module.eks.oidc_provider}:sub" = "system:serviceaccount:external-secrets:external-secrets"
          "${module.eks.oidc_provider}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.tags
}

# ── IAM Policy for ESO — SSM read access ─────────────────────────────────────
# Grants ESO permission to read ONLY the Karpenter node role name parameter.
# Follows least-privilege: scoped to a single SSM parameter ARN.
resource "aws_iam_role_policy" "external_secrets_ssm" {
  name = "ssm-read-karpenter"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = aws_ssm_parameter.karpenter_node_role_name.arn
    }]
  })
}

# ── Kubernetes ServiceAccount for ESO (Terraform-managed) ─────────────────────
# WHY Terraform creates this (not the Helm chart):
#   1. The IRSA annotation must reference the IAM role ARN created above
#   2. Keeping the SA and IAM role in the same Terraform state ensures they
#      are always in sync
#   3. The ESO Helm chart is told serviceAccount.create=false to reuse this SA
#
# The namespace is created here too so the SA can be provisioned before ArgoCD
# installs ESO — ArgoCD's CreateNamespace=true will then be a no-op.
resource "kubernetes_namespace_v1" "external_secrets" {
  metadata {
    name = "external-secrets"
  }

  depends_on = [module.eks]
}

resource "kubernetes_service_account_v1" "external_secrets" {
  metadata {
    name      = "external-secrets"
    namespace = kubernetes_namespace_v1.external_secrets.metadata[0].name
    annotations = {
      # IRSA annotation: tells the EKS OIDC provider which IAM role this SA maps to
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets.arn
    }
  }
}
