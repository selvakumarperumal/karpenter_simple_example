# ── Terraform & Provider Configuration ────────────────────────────────────────
#
# PURPOSE:
#   Declares the required Terraform version and all provider dependencies for
#   this project. Providers are configured to authenticate against the EKS
#   cluster using exec-based token retrieval (no static kubeconfig needed).
#
# PROVIDERS:
#   • aws         — Manages all AWS resources (VPC, EKS, IAM, SSM, etc.)
#   • kubernetes  — Manages Kubernetes-native resources (ServiceAccount, Namespace)
#   • helm        — Installs/manages Helm charts (ArgoCD bootstrap)
#
# AUTHENTICATION:
#   The Kubernetes and Helm providers use `exec`-based authentication via
#   `aws eks get-token`. This is the recommended approach for CI/CD pipelines
#   because it avoids storing static kubeconfig files — credentials are
#   fetched on-the-fly from STS using the caller's IAM identity.
#
# REMOTE STATE (production):
#   Uncomment the S3 backend block below to store Terraform state remotely
#   with DynamoDB-based locking. This is mandatory for team environments.
# ─────────────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.8"

  required_providers {
    # AWS Provider v6+ is required by terraform-aws-modules/eks v21+.
    # v6 introduced per-resource region support and other architectural changes.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.1.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.2.0"
    }
  }

  # ─── Uncomment for production remote state ───────────────────────────────────
  # Stores state in S3 with DynamoDB locking to prevent concurrent modifications.
  # Create the S3 bucket and DynamoDB table BEFORE running `terraform init`.
  #
  # backend "s3" {
  #   bucket         = "my-terraform-state-bucket"
  #   key            = "karpenter-demo/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-state-lock"
  #   encrypt        = true
  # }
}

# ── AWS Provider ──────────────────────────────────────────────────────────────
# All AWS resources are created in this region unless overridden per-resource.
provider "aws" {
  region = var.aws_region
}

# ── Kubernetes & Helm providers authenticate via the EKS token ──────────────
# They depend on the EKS cluster module output, so they are configured here
# using exec-based authentication (no static kubeconfig needed in CI/CD).
#
# How it works:
#   1. Terraform calls `aws eks get-token --cluster-name <name>`
#   2. The AWS CLI returns a short-lived STS token
#   3. The Kubernetes/Helm provider uses that token to authenticate
#
# This means the IAM identity running `terraform apply` must have
# `eks:DescribeCluster` permission and be granted cluster access via
# EKS Access Entries (or be the cluster creator).
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}
