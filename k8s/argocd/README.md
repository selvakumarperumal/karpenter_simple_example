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

The root app-of-apps manifest configures ArgoCD to synchronize all child configurations in the EKS cluster.

Here is the annotated version of `app-of-apps.yaml` showing detailed comments:

```yaml
# The apiVersion targets the stable custom resource API for ArgoCD Application definitions.
# If this group name is incorrect, EKS API validation checks fail.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application to be reconciled by the controller.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the root application name in ArgoCD.
  name: app-of-apps
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  # Must match the namespace defined inside terraform/helm-argocd.tf.
  namespace: argocd
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the git repository containing configuration files.
  source:
    # Git repository URL, dynamically substituted by envsubst during bootstrap.
    repoURL: ${GIT_REPOSITORY_URL}
    # Follows the HEAD commit on the target branch.
    targetRevision: HEAD
    # The path pointing to the folder containing the list of child applications.
    path: k8s/argocd/apps
    # Helm parameters passed down to the templates/ child manifests.
    helm:
      parameters:
        # Passes the repository URL parameter to child applications.
        - name: repoURL
          value: ${GIT_REPOSITORY_URL}
        # Passes the target cluster name to identify resource discovery tags.
        # Must match cluster_name in terraform/variables.tf.
        - name: clusterName
          value: ${CLUSTER_NAME}
        # Passes target AWS region, matching aws_region in terraform/variables.tf.
        - name: awsRegion
          value: ${AWS_REGION}
  # Destination where child manifests are deployed in the cluster.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # The namespace where child apps are coordinated.
    namespace: argocd
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Retry configurations on synchronization failures.
    retry:
      # Max number of retries before marking sync as failed.
      limit: 10
      # Retry delay backoff settings.
      backoff:
        # Initial wait duration before retrying.
        duration: 10s
        # Exponential growth factor for retries.
        factor: 2
        # Max retry wait duration.
        maxDuration: 3m
    # Extra sync configuration parameters.
    syncOptions:
      # Creates target namespace if it does not already exist.
      - CreateNamespace=true
      # Only syncs resources that are marked out of sync, optimizing performance.
      - ApplyOutOfSyncOnly=true
```

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
