# ArgoCD App of Apps Bootstrapper

This folder owns the root App-of-Apps bootstrap manifest for ArgoCD. Applying this manifest triggers the GitOps sync loop, which in turn configures child applications defined inside `apps/`.

## Architecture

```
+------------------------------------------------------+
|                   argocd/ Folder                     |
|                                                      |
|  +--------------------+      +--------------------+  |
|  |  app-of-apps.yaml  | ---> |       apps/        |  |
|  +--------------------+      +--------------------+  |
+------------------------------------------------------+
```

| File Name | Upstream Dependency | Downstream Target |
|:---|:---|:---|
| `app-of-apps.yaml` | `terraform/helm-argocd.tf` | `apps/` applications |

## File-by-file explanation

### app-of-apps.yaml

The `apiVersion: argoproj.io/v1alpha1` field targets the stable custom resource API for ArgoCD Application definitions. Any typo in this group causes Kubernetes API server validation failures.

The `kind: Application` field specifies that this resource is an ArgoCD Application to be reconciled by the controller.

The `metadata.name: app-of-apps` field defines the root application name in ArgoCD.

The `metadata.namespace: argocd` field deploys the application context in the namespace where the ArgoCD controller is running. It must align with the target namespace defined inside [helm-argocd.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/helm-argocd.tf#L38).

The `spec.project: default` field maps this application to the default security project profile.

The `spec.source.repoURL: ${GIT_REPOSITORY_URL}` field sets the Git repository containing configurations. The parameter is substituted by `envsubst` during bootstrap. If wrong, ArgoCD cannot fetch manifests.

The `spec.source.targetRevision: HEAD` field configures ArgoCD to watch the latest commit on the branch.

The `spec.source.path: k8s/argocd/apps` field targets the directory containing the child application list.

The `spec.source.helm.parameters` list overrides parameters inside child templates.
The `repoURL` parameter passes the repository URL down to child applications.
The `clusterName` parameter passes EKS cluster name (matches `cluster_name` inside [variables.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/variables.tf#L24)).
The `awsRegion` parameter passes target AWS region (matches `aws_region` inside [variables.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/variables.tf#L18)). If these parameters are empty or wrong, the child charts will render with missing fields.

The `spec.destination.server: https://kubernetes.default.svc` field targets the local Kubernetes API Server.

The `spec.destination.namespace: argocd` field targets the destination folder namespace.

The `spec.syncPolicy.automated.prune: true` field tells ArgoCD to delete resources from the cluster when their manifests are removed from Git.

The `spec.syncPolicy.automated.selfHeal: true` field tells the controller to automatically overwrite manual modifications in the cluster to align with Git configurations.

The `spec.syncPolicy.retry.limit: 10` field configures ArgoCD to retry synchronization up to 10 times on transient connection failures.
The `spec.syncPolicy.retry.backoff.duration: 10s` field sets initial retry delay.
The `spec.syncPolicy.retry.backoff.factor: 2` field doubles retry delays sequentially.
The `spec.syncPolicy.retry.backoff.maxDuration: 3m` field caps retry delay to 3 minutes.

The `spec.syncPolicy.syncOptions` block defines Helm engine overrides.
The `CreateNamespace=true` option tells ArgoCD to automatically create target namespaces.
The `ApplyOutOfSyncOnly=true` option tells ArgoCD to only sync resources that differ from git, optimizing performance.

## Versions and APIs used

| Component | target Version | apiVersion Group |
|:---|:---|:---|
| ArgoCD Application | latest stable | `argoproj.io/v1alpha1` |

## Prerequisites

| Dependency | Required State | Location |
|:---|:---|:---|
| EKS Cluster | Active and running | AWS |
| ArgoCD Controller | Deployed | Namespace `argocd` |

## Commands

We initialize the GitOps sync loop by substituting environment variables and applying the manifest.
```bash
export GIT_REPOSITORY_URL="https://github.com/selvakumarperumal/karpenter_simple_example.git"
export CLUSTER_NAME="karpenter-demo"
export AWS_REGION="ap-south-1"
envsubst < k8s/argocd/app-of-apps.yaml | kubectl apply -f -
```

We check the synchronization status of all applications inside the cluster.
```bash
kubectl get applications -n argocd
```

## Troubleshooting

We resolve git clone errors by checking that the repository is public or verifying that repository access credentials are added to ArgoCD settings.

We resolve empty variables rendering by checking that `GIT_REPOSITORY_URL`, `CLUSTER_NAME`, and `AWS_REGION` are exported in the shell session before running `envsubst`.

We resolve CRD validation errors by verifying that the ArgoCD controller has sufficient permissions to create resources in EKS.

## References

| Tool | Official Documentation |
|:---|:---|
| ArgoCD App of Apps | [ArgoCD Bootstrap](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) |
