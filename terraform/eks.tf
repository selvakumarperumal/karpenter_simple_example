# ── EKS Cluster ───────────────────────────────────────────────────────────────
#
# PURPOSE:
#   Creates an Amazon EKS cluster using the terraform-aws-modules/eks
#   community module (v21+). This is the foundation of the entire stack —
#   everything else (Karpenter, ArgoCD, applications) runs on top of it.
#
# ARCHITECTURE:
#   The cluster uses a two-layer node design:
#
#   Layer 1 — System Node Group (this file):
#     • Fixed-size EKS Managed Node Group (m5.large × 2)
#     • Tainted with CriticalAddonsOnly=true:NoSchedule
#     • Runs ONLY system components: Karpenter, ArgoCD, CoreDNS, kube-proxy
#     • Exists before Karpenter, so there is no chicken-and-egg problem
#
#   Layer 2 — Karpenter-managed Nodes (provisioned dynamically):
#     • Created on-demand when unschedulable application pods appear
#     • Instance type, size, and lifecycle (spot/on-demand) selected by Karpenter
#     • Configured via NodePool + EC2NodeClass (see k8s/karpenter/)
#
# MANAGED ADD-ONS:
#   EKS-managed add-ons (CoreDNS, kube-proxy, VPC-CNI, Pod Identity Agent)
#   are updated independently of node AMIs by AWS. Setting most_recent=true
#   ensures they stay current during terraform apply.
#
# ACCESS CONTROL:
#   enable_cluster_creator_admin_permissions = true grants the IAM identity
#   running `terraform apply` full cluster-admin access via EKS Access Entries.
#   For production, add additional entries for your team's IAM roles.
#
# SECURITY GROUP TAGS:
#   The node security group is tagged with karpenter.sh/discovery so Karpenter
#   can discover which security groups to attach to nodes it provisions.
# ─────────────────────────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.23.0"

  name               = local.cluster_name
  kubernetes_version = var.cluster_version

  # Expose the API server endpoint publicly (restrict in production with
  # cluster_endpoint_public_access_cidrs to your VPN/office CIDRs)
  endpoint_public_access  = true
  endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Grants the caller (the IAM identity running terraform apply) cluster-admin
  # via EKS Access Entries. No need for aws-auth ConfigMap.
  enable_cluster_creator_admin_permissions = true

  # ── Managed Add-ons ──────────────────────────────────────────────────────
  # Managed by AWS — they are updated independently of node group AMI updates.
  # Each add-on runs as a DaemonSet or Deployment on the system node group.
  addons = {
    # CoreDNS: Cluster DNS for service discovery (Deployment)
    coredns = {
      most_recent = true
    }
    # kube-proxy: Node-level network rules for Service routing (DaemonSet)
    kube-proxy = {
      most_recent = true
    }
    # VPC-CNI: Pod networking — assigns VPC IPs directly to pods (DaemonSet)
    vpc-cni = {
      most_recent = true
    }
    # Pod Identity Agent: Injects IAM credentials into pods via Pod Identity
    # associations (the modern replacement for IRSA). Required for Karpenter
    # controller to assume its IAM role without ServiceAccount annotations.
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  # ── System Node Group ────────────────────────────────────────────────────
  # This node group runs ONLY system components: Karpenter, ArgoCD,
  # CoreDNS, metrics-server, etc.
  #
  # Application pods run on Karpenter-managed nodes (NOT in this group).
  # The taint below prevents application pods from landing here.
  eks_managed_node_groups = {
    system = {
      instance_types = ["m5.large"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2

      labels = {
        role = "system"
      }

      # Prevents non-system pods from scheduling on these nodes.
      # Your app Deployments must NOT tolerate this taint.
      # System components (Karpenter, ArgoCD) tolerate it via their Helm values.
      taints = {
        system_only = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # ── Security Group Tags ──────────────────────────────────────────────────
  # Karpenter uses this tag to discover which security groups to attach
  # to the EC2 instances it provisions. Must match the value in
  # EC2NodeClass.spec.securityGroupSelectorTerms.tags.
  node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }

  tags = merge(local.tags, {
    # This tag on the cluster itself helps Karpenter identify the cluster
    "karpenter.sh/discovery" = local.cluster_name
  })
}
