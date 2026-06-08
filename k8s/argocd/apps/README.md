# ArgoCD Applications — App of Apps Pattern Deep Dive

This folder implements the **App of Apps** pattern, the core of our GitOps strategy. It contains ArgoCD `Application` manifests that instruct ArgoCD to deploy and manage all other cluster components.

---

## 1. The GitOps Pull Model

Before diving into the files, it's critical to understand the architecture. Traditional CI/CD (like Jenkins or GitHub Actions) uses a **Push Model**: a pipeline authenticates to the cluster and runs `helm upgrade` or `kubectl apply`.

This repository uses the **Pull Model**:
1. You push changes to this Git repository.
2. ArgoCD runs *inside* the Kubernetes cluster.
3. ArgoCD constantly monitors this repository.
4. When it detects a change, it automatically pulls the new manifests and reconciles the cluster state to match the Git state.

Your CI/CD pipeline never touches Kubernetes. It only builds images and updates Git. Git is the single source of truth.

---

## 2. Anatomy of an ArgoCD Application

Every file in this folder is an ArgoCD `Application` Custom Resource. Here is a breakdown of what the fields mean, using the `fastapi.yaml` as an example:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fastapi-app
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "4" # Controls boot order
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR_ORG/karpenter-demo.git # Where to pull from
    targetRevision: HEAD # Which branch or tag to track
    path: k8s/fastapi # The specific folder inside the repo to deploy
  destination:
    server: https://kubernetes.default.svc # Deploy to the local cluster
    namespace: fastapi # Deploy into this namespace
  syncPolicy:
    automated:
      prune: true # If you delete a file in Git, delete the resource in K8s
      selfHeal: true # If someone runs kubectl delete, put it right back
    syncOptions:
      - CreateNamespace=true # Make the namespace if it doesn't exist
      - ServerSideApply=true # Better conflict resolution for large CRDs
```

### The `syncPolicy` Explained
- **`automated: {}`**: Tells ArgoCD to sync immediately when Git changes. If this is missing, you must click "Sync" in the UI manually.
- **`prune: true`**: Crucial for cleanups. If you remove `ingress.yaml` from the `k8s/fastapi/` folder, ArgoCD will actively delete the Ingress from the cluster.
- **`selfHeal: true`**: Prevents configuration drift. If an admin manually edits a Deployment via `kubectl edit`, ArgoCD will instantly overwrite their changes with what is in Git.

---

## 3. Sync Waves: Orchestrating the Boot Sequence

When spinning up a new cluster, components must be installed in a specific order. For example, Karpenter needs External Secrets to be running first. ArgoCD handles this using **Sync Waves** (`argocd.argoproj.io/sync-wave`). 

ArgoCD will fully apply and wait for all resources in Wave 0 to become **Healthy** before moving to Wave 1.

```mermaid
graph TD
    subgraph Wave 0 [Wave 0: Core Operators]
        CM(cert-manager<br>Helm v1.20.2)
        ESO(external-secrets<br>Helm v2.6.0)
    end

    subgraph Wave 1 [Wave 1: Node Autoscaler]
        K(karpenter<br>OCI Helm v1.12.1)
    end

    subgraph Wave 2 [Wave 2: Node Provisioning]
        KC(karpenter-config<br>Kustomize)
    end

    subgraph Wave 3 [Wave 3: Ingress & Observability]
        IN(ingress-nginx<br>Helm v4.15.1)
        PROM(prometheus<br>Helm v86.2.0)
    end

    subgraph Wave 4 [Wave 4: Application Workloads]
        APP(fastapi<br>Plain Manifests)
    end

    Wave 0 --> Wave 1
    Wave 1 --> Wave 2
    Wave 2 --> Wave 3
    Wave 3 --> Wave 4
```

---

## 4. How to Extend the Cluster

To add a new tool (e.g. Istio, Datadog, fluent-bit), you **do not touch Terraform**. 

1. Create a new file in this directory: `datadog.yaml`
2. Define the ArgoCD `Application` pointing to the Datadog Helm chart.
3. Assign it a Sync Wave (e.g., Wave 3 for Observability).
4. Commit and push.

ArgoCD's "Root Application" (defined in `app-of-apps.yaml`) is constantly watching *this specific directory*. When you push `datadog.yaml`, ArgoCD discovers it and deploys it automatically.

---

## 5. Upgrading Cluster Components

Because everything is declarative, upgrading a component is simply a matter of changing a version string in Git.

**Example: Upgrading Karpenter**
1. Open `karpenter.yaml`.
2. Change `targetRevision: "1.12.1"` to `targetRevision: "1.13.0"`.
3. Commit and push.
4. ArgoCD pulls the new Helm chart and runs the equivalent of `helm upgrade` automatically.

---

## 6. Troubleshooting ArgoCD

### Issue: An Application is stuck in "OutOfSync"
**Cause:** The desired state in Git does not match the live state in Kubernetes, and ArgoCD cannot automatically fix it (often because `automated` sync is disabled, or a webhook is rejecting the change).
**Resolution:** Look at the Diff tab in the ArgoCD UI. It will show exactly which fields differ. If a resource is stuck, check for MutatingWebhooks that might be altering the resource after ArgoCD applies it.

### Issue: An Application is stuck in "Syncing" (Yellow Spinner)
**Cause:** ArgoCD has applied the manifests, but Kubernetes reports the resource is not healthy.
**Resolution:** 
1. Check the specific resource in the UI (e.g., a Deployment).
2. Look at the Pods underneath it. Are they `CrashLoopBackOff` or `ImagePullBackOff`?
3. This is usually an application error, not an ArgoCD error.

### Issue: Sync fails with "Pruning required" but nothing happens
**Cause:** ArgoCD is trying to delete a resource that has a finalizer, or you are trying to delete a massive namespace and the deletion is hanging.
**Resolution:** You may need to manually remove finalizers from the stuck resource using `kubectl patch`.

### Issue: "ServerSideApply" conflicts
**Cause:** Another controller (like a cloud provider operator) is fighting ArgoCD for ownership of a specific field.
**Resolution:** Ensure `ServerSideApply=true` is set in your `syncOptions`. If the conflict persists, you may need to add an `ignoreDifferences` block to your ArgoCD `Application` to tell ArgoCD to ignore that specific field.
