# ── VPC ───────────────────────────────────────────────────────────────────────
#
# PURPOSE:
#   Creates a production-grade VPC using the terraform-aws-modules/vpc
#   community module. This VPC hosts the EKS cluster, all managed node
#   groups, and Karpenter-provisioned instances.
#
# NETWORK DESIGN:
#   • CIDR: 10.0.0.0/16 (~65,000 IPs — sufficient for most clusters)
#   • 3 Private subnets (one per AZ) — EKS nodes and pods run here
#   • 3 Public subnets (one per AZ)  — ALB/NLB internet-facing load balancers
#   • Single NAT Gateway (cost-saving for non-prod; set single_nat_gateway=false
#     in production for HA across AZs)
#
# SUBNET TAGS:
#   • Public subnets:  kubernetes.io/role/elb = 1
#     → Tells AWS Load Balancer Controller to place internet-facing LBs here.
#   • Private subnets: kubernetes.io/role/internal-elb = 1
#     → Tells AWS LB Controller to place internal LBs here.
#   • Private subnets: karpenter.sh/discovery = <cluster_name>
#     → Karpenter uses this tag to discover which subnets to launch nodes into.
#     This must match the subnetSelectorTerms in EC2NodeClass.
#
# DNS:
#   Both enable_dns_hostnames and enable_dns_support are required for EKS
#   to resolve internal service endpoints and for VPC-internal DNS resolution.
# ─────────────────────────────────────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6.1"

  name = "${local.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  # Spread across the first 3 AZs for high availability
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  # NAT Gateway configuration:
  # single_nat_gateway = true  → All private subnets share one NAT (cheaper)
  # single_nat_gateway = false → One NAT per AZ (HA, required for production)
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # ── Subnet tags required by AWS Load Balancer Controller ─────────────────
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    # Karpenter uses this tag to discover which subnets to launch nodes in.
    # The value MUST match the cluster name used in EC2NodeClass subnetSelectorTerms.
    "karpenter.sh/discovery" = local.cluster_name
  }

  tags = local.tags
}
