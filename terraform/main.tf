# ── Locals & Data Sources ─────────────────────────────────────────────────────
#
# PURPOSE:
#   Defines shared local values (cluster name, common tags) and data sources
#   used across all Terraform files in this module.
#
# LOCAL VALUES:
#   • cluster_name — Single source of truth for the cluster name, derived from
#                    var.cluster_name. Referenced by VPC, EKS, IAM, and Helm.
#   • tags         — Default tags applied to every AWS resource for cost
#                    tracking, ownership, and filtering.
#
# DATA SOURCES:
#   • aws_availability_zones — Discovers available AZs in the target region.
#     Filters out Local Zones (opt-in-not-required) to ensure only standard
#     AZs are used for subnet placement.
#   • aws_caller_identity — Used in IAM policies that need the current
#     AWS account ID (e.g. for ARN construction).
# ─────────────────────────────────────────────────────────────────────────────

locals {
  cluster_name = var.cluster_name

  # Default tags applied to every AWS resource.
  # Individual resources may add extra tags via merge().
  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "karpenter-demo"
    Cluster     = var.cluster_name
  }
}

# ── Data Sources ──────────────────────────────────────────────────────────────
data "aws_availability_zones" "available" {
  # Only use AZs that are opted-in (excludes Local Zones like us-east-1-chi-1a)
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}
