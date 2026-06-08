# ── Karpenter — managed by ArgoCD (not Terraform) ─────────────────────────────
#
# PURPOSE:
#   This file is intentionally empty of Terraform resources. It serves as
#   documentation explaining WHY Karpenter is NOT installed by Terraform.
#
# ARCHITECTURE DECISION:
#   Karpenter is installed and managed entirely by ArgoCD via GitOps.
#   See: k8s/argocd/apps/karpenter.yaml
#
# WHY ArgoCD (not Terraform) manages Karpenter:
#   The system managed node group (eks_managed_node_groups.system in eks.tf)
#   runs ArgoCD on dedicated, always-on nodes BEFORE Karpenter exists.
#   This eliminates the chicken-and-egg problem:
#
#     1. Terraform creates EKS + system node group + ArgoCD (helm_release)
#     2. ArgoCD starts on system nodes (they have the CriticalAddonsOnly taint)
#     3. ArgoCD installs Karpenter via the karpenter.yaml Application (wave 1)
#     4. ArgoCD applies Karpenter config (NodePool + EC2NodeClass) (wave 2)
#     5. Karpenter is now running and ready to provision application nodes
#
# WHAT TERRAFORM STILL OWNS (see iam-karpenter.tf):
#   • IAM role for the Karpenter controller        (module.karpenter)
#   • IAM role for External Secrets Operator        (aws_iam_role.external_secrets)
#   • SSM parameter with the node IAM role name     (aws_ssm_parameter.karpenter_node_role_name)
#   • Pod Identity Association                      (module.karpenter)
#   • Karpenter ServiceAccount                      (kubernetes_service_account_v1.karpenter)
#
# EC2NodeClass:
#   Cannot be a plain static manifest because it needs the node IAM role name,
#   which is a Terraform output. Flow:
#     Terraform → SSM parameter → External Secrets Operator → K8s Secret
#     → ArgoCD PostSync Job → kubectl apply EC2NodeClass with real role name
#   See: k8s/karpenter-config/bootstrap-job.yaml
#
# NodePool:
#   Fully static — applied directly by ArgoCD Kustomize.
#   See: k8s/karpenter-config/nodepool.yaml
# ─────────────────────────────────────────────────────────────────────────────
