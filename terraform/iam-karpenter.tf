# ── Karpenter IAM ─────────────────────────────────────────────────────────────
#
# PURPOSE:
#   Creates all IAM resources required by the Karpenter autoscaler.
#   These are AWS-side resources that must exist before any Kubernetes
#   workload can use them.
#
# RESOURCES CREATED:
#   1. module.karpenter:
#      • Controller IAM Role — assumed by the Karpenter controller pod
#      • Pod Identity Association — maps (kube-system, karpenter) → IAM Role
#      • Node IAM Role — assumed by EC2 instances that Karpenter provisions
#      • Instance Profile — wraps the Node IAM Role for EC2 launch
#
# NODE ROLE NAME:
#   Hardcoded as "karpenter-node-role" (node_iam_role_name below).
#   This value is referenced directly in k8s/karpenter-config/ec2nodeclass.yaml.
#
# IDENTITY METHOD:
#   Karpenter uses EKS Pod Identity (recommended over IRSA for new clusters).
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

  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "karpenter-node-role"

  tags = local.tags
}



