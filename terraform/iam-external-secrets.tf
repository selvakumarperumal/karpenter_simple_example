# ── External Secrets Operator — IAM + Kubernetes bootstrap ───────────────────
#
# PURPOSE:
#   Creates IAM and Kubernetes resources so the External Secrets Operator
#   can authenticate to AWS and read from Secrets Manager.
#
# RESOURCES CREATED:
#   1. aws_iam_role.external_secrets
#      • IRSA role assumed by the ESO controller pod
#      • Trust policy scoped to the "external-secrets" ServiceAccount only
#
#   2. aws_iam_role_policy.external_secrets_secretsmanager
#      • Least-privilege: GetSecretValue + DescribeSecret on app secrets only
#
#   3. kubernetes_namespace_v1.external_secrets
#      • Pre-creates the namespace so the SA can be provisioned before
#        ArgoCD installs ESO (ArgoCD's CreateNamespace=true is a no-op then)
#
#   4. kubernetes_service_account_v1.external_secrets
#      • Pre-created with the IRSA annotation so ESO can auth immediately
#        when ArgoCD installs it (Helm chart runs with serviceAccount.create=false)
#
# IDENTITY METHOD:
#   ESO uses IRSA — the ServiceAccount annotation maps it to the IAM role
#   via the EKS OIDC provider. The ESO Helm chart reuses this SA.
# ─────────────────────────────────────────────────────────────────────────────

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
      # Scope to secrets under this cluster's prefix only
      Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${local.cluster_name}/*"
    }]
  })
}

# ── Kubernetes bootstrap for ESO ──────────────────────────────────────────────

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
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets.arn
    }
  }
}
