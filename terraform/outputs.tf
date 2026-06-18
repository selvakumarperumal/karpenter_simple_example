
output "cluster_name" {
  description = "EKS cluster name — used in kubectl config, Karpenter settings, and ArgoCD"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint URL"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate (used by kubectl and CI/CD)"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "configure_kubectl" {
  description = "Run this command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "karpenter_iam_role_arn" {
  description = "IAM Role ARN for the Karpenter controller (injected via Pod Identity)"
  value       = module.karpenter.iam_role_arn
}

output "karpenter_node_iam_role_name" {
  description = "IAM Role name for Karpenter-provisioned EC2 nodes (used in EC2NodeClass.spec.role)"
  value       = module.karpenter.node_iam_role_name
}

output "karpenter_node_instance_profile_name" {
  description = "Instance Profile name attached to Karpenter-provisioned nodes"
  value       = module.karpenter.instance_profile_name
}

output "vpc_id" {
  description = "VPC ID where the EKS cluster and all nodes reside"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs — EKS nodes and Karpenter instances launch here"
  value       = module.vpc.private_subnets
}

output "ecr_repository_url" {
  description = "Full ECR repository URL for the FastAPI image (e.g. 123456789012.dkr.ecr.ap-south-1.amazonaws.com/fastapi-app)"
  value       = aws_ecr_repository.fastapi.repository_url
}

output "ecr_repository_name" {
  description = "ECR repository name (used by CI pipeline to push images)"
  value       = aws_ecr_repository.fastapi.name
}
