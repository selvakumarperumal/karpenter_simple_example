# ArgoCD Child Applications Manifests Reference

This folder owns the ArgoCD Application custom resource templates. Each template configures a specific deployment target, specifying sync waves, namespaces, and Helm/Git source registries.

## Architecture

```
+-------------------------------------------------------------+
|                      templates/ Folder                      |
|                                                             |
|   +-----------------------------------------------------+   |
|   |                      Wave 0                         |   |
|   | [cert-manager] [external-secrets]                   |   |
|   | [gateway-api-crds] [istio-base]                     |   |
|   +-----------------------------------------------------+   |
|                              |                              |
|                              v                              |
|   +-----------------------------------------------------+   |
|   |                      Wave 1                         |   |
|   | [karpenter] [app-secrets] [keda] [istiod]           |   |
|   +-----------------------------------------------------+   |
|                              |                              |
|                              v                              |
|   +-----------------------------------------------------+   |
|   |                      Wave 2                         |   |
|   | [karpenter-config]                                  |   |
|   +-----------------------------------------------------+   |
|                              |                              |
|                              v                              |
|   +-----------------------------------------------------+   |
|   |                      Wave 3                         |   |
|   | [prometheus]                                        |   |
|   +-----------------------------------------------------+   |
|                              |                              |
|                              v                              |
|   +-----------------------------------------------------+   |
|   |                      Wave 4                         |   |
|   | [fastapi]                                           |   |
|   +-----------------------------------------------------+   |
+-------------------------------------------------------------+
```

| Component Application | Sync Wave | Sourced Registry | Destination Namespace |
|:---|:---|:---|:---|
| `cert-manager.yaml` | `0` | `https://charts.jetstack.io` | `cert-manager` |
| `external-secrets.yaml` | `0` | `https://charts.external-secrets.io` | `external-secrets` |
| `gateway-api-crds.yaml` | `0` | `https://kubernetes-sigs.github.io/gateway-api` | `gateway-system` |
| `istio-base.yaml` | `0` | `https://istio-release.storage.googleapis.com/charts` | `istio-system` |
| `karpenter.yaml` | `1` | `oci://public.ecr.aws/karpenter` | `kube-system` |
| `app-secrets.yaml` | `1` | Local repo (`k8s/secrets`) | `fastapi` |
| `keda.yaml` | `1` | `https://kedacore.github.io/charts` | `keda` |
| `istiod.yaml` | `1` | `https://istio-release.storage.googleapis.com/charts` | `istio-system` |
| `karpenter-config.yaml` | `2` | Local repo (`k8s/karpenter-config`) | `kube-system` |
| `prometheus.yaml` | `3` | `https://prometheus-community.github.io/helm-charts` | `monitoring` |
| `fastapi.yaml` | `4` | Local repo (`k8s/fastapi`) | `fastapi` |

## File-by-file explanation

### cert-manager.yaml

The `apiVersion: argoproj.io/v1alpha1` field targets the stable custom resource API for ArgoCD Application definitions. Any typo in this group causes Kubernetes API server validation failures.

The `kind: Application` field specifies that this resource is an ArgoCD Application to be reconciled by the controller.

The `metadata.name: cert-manager` field defines the application name.

The `metadata.namespace: argocd` field deploys the application context in the namespace where the ArgoCD controller is running.

The `metadata.annotations.argocd.argoproj.io/sync-wave: "0"` annotation assigns this deployment to wave 0. This ensures cert-manager is running early to configure certificate resources for subsequent services.

The `spec.project: default` field maps this application to the default project security profile.

The `spec.source.repoURL: https://charts.jetstack.io` field targets the official Jetstack repository.

The `spec.source.chart: cert-manager` field specifies the target chart.

The `spec.source.targetRevision: v1.17.0` field pins the deployment to version 1.17.0.

The `spec.source.helm.parameters` block configures parameters.
The `installCRDs` parameter with value `true` tells Helm to automatically deploy custom resource definitions. If missing, cert-manager fails validation due to missing schema definitions.

The `spec.destination.server: https://kubernetes.default.svc` field targets the local API server.

The `spec.destination.namespace: cert-manager` field targets the `cert-manager` namespace.

The `spec.syncPolicy.automated.prune: true` field tells ArgoCD to delete resources from the cluster when their manifests are removed from Git.

The `spec.syncPolicy.automated.selfHeal: true` field tells the controller to automatically overwrite manual modifications in the cluster to align with Git configurations.

The `spec.syncPolicy.syncOptions` block defines Helm engine overrides.
The `CreateNamespace=true` option tells ArgoCD to automatically create namespaces.
The `ServerSideApply=true` option tells ArgoCD to use server-side apply.

### external-secrets.yaml

The `apiVersion: argoproj.io/v1alpha1` field targets the stable custom resource API.

The `kind: Application` field specifies that this resource is an ArgoCD Application.

The `metadata.name: external-secrets` field defines the application name.

The `metadata.namespace: argocd` field targets the controller namespace.

The `metadata.annotations.argocd.argoproj.io/sync-wave: "0"` annotation assigns this deployment to wave 0. This ensures that the secrets operator CRDs are deployed before we attempt to parse any `ExternalSecret` templates in wave 1.

The `spec.project: default` field maps this application to the default project profile.

The `spec.source.repoURL: https://charts.external-secrets.io` field targets the official operator chart repository.

The `spec.source.chart: external-secrets` field specifies the operator chart.

The `spec.source.targetRevision: 0.14.2` field pins the deployment to version 0.14.2.

The `spec.source.helm.parameters` list overrides parameters.
The `installCRDs` parameter with value `true` installs CRDs. If missing, subsequent `ExternalSecret` resources fail to load.

The `spec.destination.server: https://kubernetes.default.svc` field targets the local server.

The `spec.destination.namespace: external-secrets` field targets the `external-secrets` namespace (matches namespace configured in [iam-external-secrets.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/iam-external-secrets.tf#L73)).

The `spec.syncPolicy.automated.prune: true` and `selfHeal: true` settings enforce Git version alignments.

The `spec.syncPolicy.syncOptions` block defines Helm engine overrides.
The `CreateNamespace=true` and `ServerSideApply=true` options configure deployment behaviors.

### gateway-api-crds.yaml

The `apiVersion: argoproj.io/v1alpha1` field targets the stable custom resource API.

The `kind: Application` field specifies that this resource is an ArgoCD Application.

The `metadata.name: gateway-api-crds` field defines the application name.

The `metadata.namespace: argocd` field targets the controller namespace.

The `metadata.annotations.argocd.argoproj.io/sync-wave: "0"` annotation assigns this deployment to wave 0. This ensures that the Gateway API CRDs are deployed before we attempt to parse any `Gateway` or `HTTPRoute` templates in wave 4.

The `spec.project: default` field maps this application to the default project profile.

The `spec.source.repoURL: https://kubernetes-sigs.github.io/gateway-api` field targets the official Kubernetes SIGs repository.

The `spec.source.chart: gateway-api-crds` field specifies the CRDs chart.

The `spec.source.targetRevision: 1.2.1` field pins the deployment to version 1.2.1.

The `spec.destination.server: https://kubernetes.default.svc` field targets the local server.

The `spec.destination.namespace: gateway-system` field targets the `gateway-system` namespace.

The `spec.syncPolicy.automated.prune: true` and `selfHeal: true` settings enforce Git version alignments.

The `spec.syncPolicy.syncOptions` block defines Helm engine overrides.
The `CreateNamespace=true` and `ServerSideApply=true` options configure deployment behaviors.

### istio-base.yaml

The `apiVersion: argoproj.io/v1alpha1` field targets the stable custom resource API.

The `kind: Application` field specifies that this resource is an ArgoCD Application.

The `metadata.name: istio-base` field defines the application name.

The `metadata.namespace: argocd` field targets the controller namespace.

The `metadata.annotations.argocd.argoproj.io/sync-wave: "0"` annotation assigns this deployment to wave 0. This ensures that the Istio base CRDs and ClusterRoles are deployed before `istiod` starts in wave 1.

The `spec.project: default` field maps this application to the default project profile.

The `spec.source.repoURL: https://istio-release.storage.googleapis.com/charts` field targets the official Istio repository.

The `spec.source.chart: base` field specifies the base configurations chart.

The `spec.source.targetRevision: 1.30.1` field pins the deployment to version 1.30.1.

The `spec.source.helm.parameters` block configures parameters.
The `defaultRevision` parameter with value `default` configures revision tagging.

The `spec.destination.server: https://kubernetes.default.svc` field targets the local server.

The `spec.destination.namespace: istio-system` field targets the `istio-system` namespace.

The `spec.syncPolicy.automated.prune: true` and `selfHeal: true` settings enforce Git version alignments.

The `spec.syncPolicy.syncOptions` block defines Helm engine overrides.
The `CreateNamespace=true` and `ServerSideApply=true` options configure deployment behaviors.

### app-secrets.yaml

The `apiVersion: argoproj.io/v1alpha1` field targets the stable custom resource API.

The `kind: Application` field specifies that this resource is an ArgoCD Application.

The `metadata.name: app-secrets` field defines the application name.

The `metadata.namespace: argocd` field targets the controller namespace.

The `metadata.annotations.argocd.argoproj.io/sync-wave: "1"` annotation assigns this deployment to wave 1. This ensures that the secrets operator (wave 0) is running before we attempt to parse `ExternalSecret` templates.

The `spec.project: default` field maps this application to the default project profile.

The `spec.source.repoURL: {{ .Values.repoURL | quote }}` field points to the Git repository containing configurations.

The `spec.source.targetRevision: HEAD` field configures ArgoCD to follow the latest commit on the branch.

The `spec.source.path: k8s/secrets` field targets the local folder path containing secrets templates.

The `spec.source.helm.parameters` list overrides parameters.
The `clusterName` parameter passes EKS cluster name (matches `clusterName` inside [values.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/argocd/apps/values.yaml#L2)).
The `awsRegion` parameter passes target AWS region (matches `awsRegion` inside [values.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/argocd/apps/values.yaml#L3)).

The `spec.destination.server: https://kubernetes.default.svc` field targets the local server.

The `spec.destination.namespace: fastapi` field targets the `fastapi` namespace.

The `spec.syncPolicy.automated.prune: true` and `selfHeal: true` settings enforce Git alignments.

The `spec.syncPolicy.syncOptions` block defines Helm engine overrides.
The `CreateNamespace=true` and `ServerSideApply=true` options configure deployment behaviors.

### istiod.yaml

The `apiVersion: argoproj.io/v1alpha1` field targets the stable custom resource API.

The `kind: Application` field specifies that this resource is an ArgoCD Application.

The `metadata.name: istiod` field defines the application name.

The `metadata.namespace: argocd` field targets the controller namespace.

The `metadata.annotations.argocd.argoproj.io/sync-wave: "1"` annotation assigns this deployment to wave 1. This ensures that the base CRDs are running before we start `istiod`.

The `spec.project: default` field maps this application to the default project profile.

The `spec.source.repoURL: https://istio-release.storage.googleapis.com/charts` field targets the official Istio repository.

The `spec.source.chart: istiod` field specifies the control plane chart.

The `spec.source.targetRevision: 1.30.1` field pins the deployment to version 1.30.1 (matches version inside [istio-base.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/argocd/apps/templates/istio-base.yaml#L31)).

The `spec.source.helm.parameters` list overrides parameters.
The `global.proxy.autoInject` parameter with value `enabled` enables sidecar injection.
The `meshConfig.enableTracing` parameter with value `false` disables tracing.
The `meshConfig.accessLogFile` parameter with value `/dev/stdout` configures logs.

The `spec.destination.server: https://kubernetes.default.svc` field targets the local server.

The `spec.destination.namespace: istio-system` field targets the `istio-system` namespace.

The `spec.syncPolicy.automated.prune: true` and `selfHeal: true` settings enforce Git alignments.

The `spec.syncPolicy.syncOptions` block defines Helm engine overrides.
The `CreateNamespace=false` and `ServerSideApply=true` options configure deployment behaviors.

### karpenter.yaml

The `apiVersion: argoproj.io/v1alpha1` field targets the stable custom resource API.

The `kind: Application` field specifies that this resource is an ArgoCD Application.

The `metadata.name: karpenter` field defines the application name.

The `metadata.namespace: argocd` field targets the controller namespace.

The `metadata.annotations.argocd.argoproj.io/sync-wave: "1"` annotation assigns this deployment to wave 1. This ensures that Karpenter is running before we deploy provisioning configs in wave 2.

The `spec.project: default` field maps this application to the default project profile.

The `spec.source.repoURL: oci://public.ecr.aws/karpenter` field targets the ECR OCI registry distribution channel.

The `spec.source.chart: karpenter` field specifies the controller chart.

The `spec.source.targetRevision: 1.13.0` field pins the deployment to version 1.13.0.

The `spec.source.helm.parameters` list overrides parameters.
The `settings.clusterName` parameter passes EKS cluster name (matches `clusterName` inside [values.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/argocd/apps/values.yaml#L2)).
The `settings.interruptionQueue` parameter passes SQS queue name for interruption events.
The `controller.resources.requests.cpu` parameter sets CPU requests to `1`.
The `controller.resources.requests.memory` parameter sets memory requests to `1Gi`.
The `controller.resources.limits.cpu` parameter sets CPU limits to `1`.
The `controller.resources.limits.memory` parameter sets memory limits to `1Gi`.
The `serviceAccount.name` parameter sets the controller ServiceAccount name to `karpenter`.

The `spec.destination.server: https://kubernetes.default.svc` field targets the local server.

The `spec.destination.namespace: kube-system` field targets the `kube-system` namespace.

The `spec.syncPolicy.automated.prune: true` and `selfHeal: true` settings enforce Git alignments.

The `spec.syncPolicy.syncOptions` block defines Helm engine overrides.
The `ServerSideApply=true` option configures deployment behaviors.

### keda.yaml

The `apiVersion: argoproj.io/v1alpha1` field targets the stable custom resource API.

The `kind: Application` field specifies that this resource is an ArgoCD Application.

The `metadata.name: keda` field defines the application name.

The `metadata.namespace: argocd` field targets the controller namespace.

The `metadata.annotations.argocd.argoproj.io/sync-wave: "1"` annotation assigns this deployment to wave 1. This ensures that KEDA is running before we deploy `ScaledObject` templates.

The `spec.project: default` field maps this application to the default project profile.

The `spec.source.repoURL: https://kedacore.github.io/charts` field targets the official KEDA repository.

The `spec.source.chart: keda` field specifies the controller chart.

The `spec.source.targetRevision: 2.20.1` field pins the deployment to version 2.20.1.

The `spec.source.helm.parameters` list overrides parameters.
The `webhooks.enabled` parameter with value `true` enables webhooks validation.
The `serviceAccount.name` parameter sets the operator ServiceAccount name to `keda-operator`.

The `spec.destination.server: https://kubernetes.default.svc` field targets the local server.

The `spec.destination.namespace: keda` field targets the `keda` namespace.

The `spec.syncPolicy.automated.prune: true` and `selfHeal: true` settings enforce Git alignments.

The `spec.syncPolicy.syncOptions` block defines Helm engine overrides.
The `CreateNamespace=true` and `ServerSideApply=true` options configure deployment behaviors.

### karpenter-config.yaml

The `apiVersion: argoproj.io/v1alpha1` field targets the stable custom resource API.

The `kind: Application` field specifies that this resource is an ArgoCD Application.

The `metadata.name: karpenter-config` field defines the application name.

The `metadata.namespace: argocd` field targets the controller namespace.

The `metadata.annotations.argocd.argoproj.io/sync-wave: "2"` annotation assigns this deployment to wave 2. This ensures that Karpenter CRDs are registered before we apply configs.

The `spec.project: default` field maps this application to the default project profile.

The `spec.source.repoURL: {{ .Values.repoURL | quote }}` field points to the Git repository containing configurations.

The `spec.source.targetRevision: HEAD` field configures ArgoCD to follow the latest commit on the branch.

The `spec.source.path: k8s/karpenter-config` field targets the local folder path containing templates.

... (same config format structure for `prometheus.yaml` and `fastapi.yaml` templates inside `templates/` to represent values and chart parameters).

## Versions and APIs used

| Component | Target Version | apiVersion Group |
|:---|:---|:---|
| ArgoCD Application | latest stable | `argoproj.io/v1alpha1` |

## Prerequisites

| Requirement | Target Configuration | Location |
|:---|:---|:---|
| Parent App of Apps | Deployed and running | Namespace `argocd` |

## Commands

We render the Helm templates locally to verify that all variables parse correctly before committing changes.
```bash
helm template k8s/argocd/apps
```

## Troubleshooting

We resolve validation errors during apply by verifying that the Gateway API CRDs and operator CRDs are installed before template files are parsed.

We resolve namespace creation errors by ensuring that namespaces are declared in sync wave 0 or managed by ArgoCD namespaces auto-creation settings.

## References

| Tool | Official Documentation |
|:---|:---|
| ArgoCD Sync | [ArgoCD Documentation](https://argo-cd.readthedocs.io/en/stable/) |
