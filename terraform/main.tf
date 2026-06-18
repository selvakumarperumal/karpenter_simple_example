
locals {
  cluster_name = var.cluster_name

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "karpenter-demo"
    Cluster     = var.cluster_name
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}
