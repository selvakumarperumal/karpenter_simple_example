
variable "aws_region" {
  description = "AWS region to deploy all resources into (VPC, EKS, IAM, etc.)"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "EKS cluster name — also used for Karpenter discovery tags and SSM parameter paths"
  type        = string
  default     = "karpenter-demo"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster (must be supported by EKS)"
  type        = string
  default     = "1.33"
}

variable "environment" {
  description = "Environment tag applied to all resources (e.g. production, staging, dev)"
  type        = string
  default     = "production"
}

variable "git_repository_url" {
  description = "Git repository URL that ArgoCD will watch for Kubernetes manifests"
  type        = string
  default = "https://github.com/selvakumarperumal/karpenter_simple_example.git"
}
