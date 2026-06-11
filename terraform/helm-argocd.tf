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
#     Wave 0: cert-manager
#     Wave 1: karpenter (Helm chart)
#     Wave 2: karpenter-config (NodePool + EC2NodeClass via Kustomize)
#     Wave 3: ingress-nginx, prometheus
#     Wave 4: fastapi application
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

# ── Bootstrap the App of Apps ──────────────────────────────────────────────────
# PURPOSE:
#   Applies the single "App of Apps" Application manifest. This is the LAST
#   Terraform-managed step — after this, all future changes go through
#   Git → ArgoCD sync, never through kubectl or Helm directly.
#
# HOW IT WORKS:
#   1. The app-of-apps Application points ArgoCD at k8s/argocd/apps/
#   2. ArgoCD reads all Application manifests in that directory
#   3. Each Application installs a tool or service (cert-manager, Karpenter, etc.)
#   4. Sync waves ensure correct ordering (cert-manager → Karpenter → apps)
#
# ENVSUBST:
#   The app-of-apps.yaml uses ${GIT_REPOSITORY_URL} as a placeholder.
#   envsubst replaces it at apply time with the Terraform variable value.
#   This avoids hardcoding the Git URL in the manifest.
#
# RE-TRIGGER LOGIC:
#   The null_resource re-runs if:
#   • ArgoCD version changes (ensures App of Apps is reapplied after upgrade)
#   • Git repository URL changes
#   • ESO ServiceAccount changes (ensures IRSA annotation is current before wave 0)
resource "null_resource" "argocd_app_of_apps" {
  triggers = {
    argocd_version = helm_release.argocd.version
    git_repo       = var.git_repository_url
    eso_sa_version = kubernetes_service_account_v1.external_secrets.metadata[0].resource_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig \
        --name ${module.eks.cluster_name} \
        --region ${var.aws_region}

      export GIT_REPOSITORY_URL="${var.git_repository_url}"

      envsubst < ${path.module}/../k8s/argocd/app-of-apps.yaml | kubectl apply -f -
    EOT
  }

  # ESO SA must exist before ArgoCD syncs wave-0 so ESO can authenticate immediately.
  depends_on = [helm_release.argocd, kubernetes_service_account_v1.external_secrets]
}
