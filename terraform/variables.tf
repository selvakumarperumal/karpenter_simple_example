# ── Input Variables ────────────────────────────────────────────────────────────
#
# PURPOSE:
#   Defines all configurable parameters for the infrastructure stack.
#   Override defaults via terraform.tfvars, CLI flags (-var), or environment
#   variables (TF_VAR_<name>).
#
# USAGE:
#   terraform apply \
#     -var='cluster_name=my-cluster' \
#     -var='git_repository_url=https://github.com/myorg/myrepo.git'
#
# SECURITY NOTE:
#   Never commit .tfvars files containing secrets. Use a secrets manager
#   or CI/CD variable injection instead.
# ─────────────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy all resources into (VPC, EKS, IAM, etc.)"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name — also used for Karpenter discovery tags and SSM parameter paths"
  type        = string
  default     = "karpenter-demo"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster (must be supported by EKS)"
  type        = string
  default     = "1.32"
}

variable "environment" {
  description = "Environment tag applied to all resources (e.g. production, staging, dev)"
  type        = string
  default     = "production"
}

variable "git_repository_url" {
  description = "Git repository URL that ArgoCD will watch for Kubernetes manifests"
  type        = string
  # Override this with your actual repo:
  #   terraform apply -var='git_repository_url=https://github.com/selvakumarperumal/karpenter_simple_example.git'
  default = "https://github.com/selvakumarperumal/karpenter_simple_example.git"
}
