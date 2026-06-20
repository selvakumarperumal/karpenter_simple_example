
resource "terraform_data" "pre_destroy_cleanup" {
  input = {
    cluster_name = module.eks.cluster_name
    aws_region   = var.aws_region
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -e

      CLUSTER="${self.input.cluster_name}"
      REGION="${self.input.aws_region}"

      echo "==> Configuring kubectl for cluster: $CLUSTER"
      aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION"

      echo "==> Deleting app-of-apps ArgoCD Application (cascade foreground)"
      kubectl delete application app-of-apps -n argocd \
        --cascade=foreground \
        --ignore-not-found=true \
        --timeout=300s

      echo "==> Waiting for application namespaces to terminate"
      for NS in fastapi monitoring keda external-secrets cert-manager istio-system gateway-system; do
        if kubectl get namespace "$NS" &>/dev/null; then
          echo "  Waiting for namespace $NS to terminate..."
          kubectl wait --for=delete namespace/"$NS" --timeout=300s || true
        fi
      done

      echo "==> Deleting remaining Karpenter NodeClaims (if any)"
      kubectl delete nodeclaims --all --ignore-not-found=true --timeout=120s || true

      echo "==> Deleting remaining Karpenter NodePools (if any)"
      kubectl delete nodepools --all --ignore-not-found=true --timeout=60s || true

      echo "==> Deleting remaining Karpenter EC2NodeClasses (if any)"
      kubectl delete ec2nodeclasses --all --ignore-not-found=true --timeout=60s || true

      echo "==> Waiting for Karpenter nodes to drain and terminate"
      KARPENTER_NODES=$(kubectl get nodes -l role=application -o name 2>/dev/null || true)
      if [ -n "$KARPENTER_NODES" ]; then
        echo "$KARPENTER_NODES" | xargs kubectl delete --ignore-not-found=true --timeout=120s || true
      fi

      echo "==> Pre-destroy cleanup complete"
    EOT
  }

  depends_on = [
    helm_release.argocd,
    module.eks,
  ]
}
