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
#   • Node IAM role for EC2 instances              (module.karpenter, hardcoded "karpenter-node-role")
#   • Pod Identity Association                      (module.karpenter)
#
# EC2NodeClass:
#   Applied as a plain static manifest by ArgoCD Kustomize.
#   The IAM role name is hardcoded as "karpenter-node-role".
#   See: k8s/karpenter-config/ec2nodeclass.yaml
#
# NodePool:
#   Fully static — applied directly by ArgoCD Kustomize.
#   See: k8s/karpenter-config/nodepool.yaml
# ─────────────────────────────────────────────────────────────────────────────
