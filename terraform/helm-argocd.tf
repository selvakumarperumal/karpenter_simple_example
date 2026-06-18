resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.5.20"
  namespace  = "argocd"

  create_namespace = true

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

  depends_on = [module.eks]
}

