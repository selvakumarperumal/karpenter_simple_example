# ── ArgoCD — installed by Terraform (helm_release) ────────────────────────────
#
# PURPOSE:
#   Bootstraps ArgoCD into the EKS cluster via Helm. ArgoCD is the GitOps
#   engine that manages ALL other Kubernetes workloads after this initial
#   installation.
#
# WHY TERRAFORM MANAGES ArgoCD:
#   ArgoCD is the bootstrapper for everything else (the "App of Apps" root).
#   It must be installed before it can manage any other Helm chart or manifest.
#   Terraform installs it once; after that, ArgoCD can self-manage (its own
#   Application can update itself from Git on version bumps).
#
# AFTER TERRAFORM RUNS:
#   ArgoCD reads k8s/argocd/apps/ from Git and deploys (in sync-wave order):
#     Wave 0: cert-manager, external-secrets, istio-base, gateway-api-crds
#     Wave 1: karpenter, app-secrets, keda, istiod (control plane)
#     Wave 2: karpenter-config
#     Wave 3: prometheus
#     Wave 4: fastapi (Deployments + Gateway API Gateway + HTTPRoute + DestinationRule)
#   No more kubectl or Helm commands are needed by the platform team.
#
# OCI REPOSITORY REGISTRATION:
#   The Karpenter Helm chart is hosted on public ECR as an OCI artifact.
#   ArgoCD must have this registry pre-registered to pull the chart.
#   No credentials are needed (public ECR), but the URL must be known.
#
# ACCESS:
#   ArgoCD is exposed as ClusterIP only. Access via:
#     kubectl port-forward svc/argocd-server -n argocd 8080:443
#   Or configure an Ingress/Gateway for production access.
# ─────────────────────────────────────────────────────────────────────────────
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.5.20"    # Pin this — ArgoCD upgrades itself via GitOps after bootstrap
  namespace  = "argocd"

  create_namespace = true

  # Expose only via ClusterIP; access through kubectl port-forward or Ingress
  # Register the Karpenter OCI Helm registry so ArgoCD can pull the chart.
  # Public ECR requires no credentials but must be pre-registered.
  set = [
    {
      name  = "server.service.type"
      value = "ClusterIP"
    },
    {
      name  = "configs.repositories.karpenter-oci.url"
      value = "oci://public.ecr.aws/karpenter"
    },
    {
      name  = "configs.repositories.karpenter-oci.name"
      value = "karpenter-oci"
    },
    {
      name  = "configs.repositories.karpenter-oci.type"
      value = "helm"
    },
    {
      name  = "configs.repositories.karpenter-oci.enableOCI"
      value = "true"
    }
  ]

  wait    = true
  timeout = 300

  # ArgoCD runs on the system managed node group (eks_managed_node_groups.system).
  # Those nodes exist before Karpenter is installed, so there is no dependency.
  depends_on = [module.eks]
}

# NOTE: The root App of Apps bootstrap manifest (k8s/argocd/app-of-apps.yaml) is NOT
# applied by Terraform. You must apply it manually using the instructions in the README.
