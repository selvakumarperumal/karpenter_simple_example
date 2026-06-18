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

The cert-manager manifest initiates TLS certificate capabilities.

Here is the annotated version of `cert-manager.yaml` showing detailed comments:

```yaml
# Targets the stable custom resource API for ArgoCD Application definitions.
# If this group name is incorrect, API validation fails.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application to be reconciled by the controller.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the application name in ArgoCD.
  name: cert-manager
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  # Must match the namespace defined inside terraform/helm-argocd.tf.
  namespace: argocd
  # Annotations configuring sync sequence priority.
  annotations:
    # Human-readable explanation of this component's purpose.
    kubernetes.io/description: "Deploys cert-manager to manage TLS certificates inside EKS"
    # Sync wave 0 installs cert-manager early before subsequent apps require certs.
    argocd.argoproj.io/sync-wave: "0"
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the registry hosting the chart.
  source:
    # Official Jetstack Helm chart repository URL.
    repoURL: https://charts.jetstack.io
    # The target chart to install.
    chart: cert-manager
    # Pin version for stability.
    targetRevision: "v1.20.2"
    # Helm parameters overriding the chart defaults.
    helm:
      parameters:
        # Installs custom resource definitions automatically.
        - name: crds.enabled
          value: "true"
  # Destination where manifests are deployed in EKS.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # The namespace where cert-manager is deployed.
    namespace: cert-manager
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Extra sync configuration parameters.
    syncOptions:
      # Creates target namespace if it does not already exist.
      - CreateNamespace=true
      # Uses server side apply to prevent resource length validation errors.
      - ServerSideApply=true
```

### external-secrets.yaml

The external-secrets manifest initiates secrets syncing operator.

Here is the annotated version of `external-secrets.yaml` showing detailed comments:

```yaml
# Targets the stable custom resource API for ArgoCD Application definitions.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the application name in ArgoCD.
  name: external-secrets
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  namespace: argocd
  # Annotations configuring sync sequence priority.
  annotations:
    # Human-readable explanation of this component's purpose.
    kubernetes.io/description: "Installs External Secrets Operator to sync secrets from AWS Secrets Manager to Kubernetes"
    # Sync wave 0 installs operator before any ExternalSecrets are parsed in wave 1.
    argocd.argoproj.io/sync-wave: "0"
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the registry hosting the chart.
  source:
    # Official External Secrets Helm chart repository URL.
    repoURL: https://charts.external-secrets.io
    # The target chart to install.
    chart: external-secrets
    # Pin version for stability.
    targetRevision: "0.10.9"
    # Helm parameters overriding the chart defaults.
    helm:
      parameters:
        # Installs custom resource definitions automatically.
        - name: installCRDs
          value: "true"
        # Disable ServiceAccount creation inside Helm, as IRSA creates it in Terraform.
        # If set to true, Helm orphans the IRSA annotation and breaks AWS IAM access.
        - name: serviceAccount.create
          value: "false"
        # Must match EKS ServiceAccount linked to IAM Role for Service Accounts.
        # Created in terraform/iam-external-secrets.tf.
        - name: serviceAccount.name
          value: "external-secrets"
  # Destination where manifests are deployed in EKS.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # Must match the namespace configured in terraform/iam-external-secrets.tf.
    namespace: external-secrets
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Extra sync configuration parameters.
    syncOptions:
      # Namespace is already created in terraform/iam-external-secrets.tf.
      - CreateNamespace=false
```

### gateway-api-crds.yaml

The gateway-api-crds manifest initiates SIG Gateway API definitions.

Here is the annotated version of `gateway-api-crds.yaml` showing detailed comments:

```yaml
# Targets the stable custom resource API for ArgoCD Application definitions.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the application name in ArgoCD.
  name: gateway-api-crds
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  namespace: argocd
  # Annotations configuring sync sequence priority.
  annotations:
    # Human-readable explanation of this component's purpose.
    kubernetes.io/description: "Installs the official Kubernetes Gateway API CRDs"
    # Wave 0 ensures API schemas are registered before routing configs load.
    argocd.argoproj.io/sync-wave: "0"
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the registry hosting the chart.
  source:
    # Target git repo containing Gateway API CRDs.
    repoURL: https://github.com/kubernetes-sigs/gateway-api
    # Pin version for stability.
    targetRevision: "v1.5.1"
    # Local path inside the repository to pull standard CRD manifests.
    path: config/crd/standard
  # Destination where manifests are deployed in EKS.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # The namespace where CRDs are applied.
    namespace: gateway-system
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Extra sync configuration parameters.
    syncOptions:
      # Creates target namespace if it does not already exist.
      - CreateNamespace=true
      # Uses server side apply to prevent resource length validation errors.
      - ServerSideApply=true
```

### istio-base.yaml

The istio-base manifest configures root Istio resources.

Here is the annotated version of `istio-base.yaml` showing detailed comments:

```yaml
# Targets the stable custom resource API for ArgoCD Application definitions.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the application name in ArgoCD.
  name: istio-base
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  namespace: argocd
  # Annotations configuring sync sequence priority.
  annotations:
    # Human-readable explanation of this component's purpose.
    kubernetes.io/description: "Installs base Istio resources, including cluster roles and CRDs"
    # Sync wave 0 installs base definitions before istiod control plane in wave 1.
    argocd.argoproj.io/sync-wave: "0"
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the registry hosting the chart.
  source:
    # Official Istio Helm chart registry URL.
    repoURL: https://istio-release.storage.googleapis.com/charts
    # The target chart to install.
    chart: base
    # Pin version for stability.
    targetRevision: "1.30.1"
    # Helm parameters overriding the chart defaults.
    helm:
      parameters:
        # Sets the default revision naming schema for the mesh configuration.
        - name: defaultRevision
          value: "default"
  # Destination where manifests are deployed in EKS.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # Control plane base resources go into istio-system.
    namespace: istio-system
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Extra sync configuration parameters.
    syncOptions:
      # Creates target namespace if it does not already exist.
      - CreateNamespace=true
      # Uses server side apply to prevent resource length validation errors.
      - ServerSideApply=true
```

### karpenter.yaml

The karpenter manifest installs EKS node provisioner operator.

Here is the annotated version of `karpenter.yaml` showing detailed comments:

```yaml
# Targets the stable custom resource API for ArgoCD Application definitions.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the application name in ArgoCD.
  name: karpenter
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  namespace: argocd
  # Annotations configuring sync sequence priority.
  annotations:
    # Human-readable explanation of this component's purpose.
    kubernetes.io/description: "Installs the Karpenter autoscaling controller into the cluster"
    # Wave 1 installs Karpenter operator after CRDs and before configurations.
    argocd.argoproj.io/sync-wave: "1"
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the registry hosting the chart.
  source:
    # AWS private ECR OCI registry URL channel.
    repoURL: oci://public.ecr.aws/karpenter
    # The target chart to install.
    chart: karpenter
    # Pin version for stability.
    targetRevision: "1.13.0"
    # Helm parameters overriding the chart defaults.
    helm:
      parameters:
        # Injects the target cluster name, matching values.yaml.
        - name: settings.clusterName
          value: {{ .Values.clusterName | quote }}
        # SQS queue for interruption events, created in terraform/iam-karpenter.tf.
        - name: settings.interruptionQueue
          value: {{ .Values.clusterName | quote }}
        # Karpenter controller resource boundaries requests.
        - name: controller.resources.requests.cpu
          value: "1"
        - name: controller.resources.requests.memory
          value: 1Gi
        # Karpenter controller resource boundaries limits.
        - name: controller.resources.limits.cpu
          value: "1"
        - name: controller.resources.limits.memory
          value: 1Gi
        # Service account name configured in terraform/helm-karpenter.tf.
        # If mismatched, Karpenter pod cannot authenticate to AWS EC2 APIs.
        - name: serviceAccount.name
          value: karpenter
  # Destination where manifests are deployed in EKS.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # Deploys in system namespace.
    namespace: kube-system
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Extra sync configuration parameters.
    syncOptions:
      # Uses server side apply to prevent resource length validation errors.
      - ServerSideApply=true
```

### app-secrets.yaml

The app-secrets manifest maps EKS configurations to secrets.

Here is the annotated version of `app-secrets.yaml` showing detailed comments:

```yaml
# Targets the stable custom resource API for ArgoCD Application definitions.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the application name in ArgoCD.
  name: app-secrets
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  namespace: argocd
  # Annotations configuring sync sequence priority.
  annotations:
    # Human-readable explanation of this component's purpose.
    kubernetes.io/description: "Applies the ClusterSecretStore and application-level ExternalSecrets"
    # Wave 1 is checked out after external-secrets operator (wave 0) is ready.
    argocd.argoproj.io/sync-wave: "1"
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the local directory.
  source:
    # Local Git repository path, matching values.yaml.
    repoURL: {{ .Values.repoURL | quote }}
    # Follows the HEAD commit.
    targetRevision: HEAD
    # Path inside local repository where configurations reside.
    path: k8s/secrets
    # Helm parameters overriding the chart defaults.
    helm:
      parameters:
        # Passes the AWS region down to local templates.
        - name: awsRegion
          value: {{ .Values.awsRegion | quote }}
        # Passes the cluster name down to local templates.
        - name: clusterName
          value: {{ .Values.clusterName | quote }}
  # Destination where manifests are deployed in EKS.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # Deploys secrets inside application namespace.
    namespace: fastapi
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Extra sync configuration parameters.
    syncOptions:
      # Creates target namespace if it does not already exist.
      - CreateNamespace=true
      # Uses server side apply to prevent resource length validation errors.
      - ServerSideApply=true
```

### keda.yaml

The keda manifest configures event-driven autoscaling tools.

Here is the annotated version of `keda.yaml` showing detailed comments:

```yaml
# Targets the stable custom resource API for ArgoCD Application definitions.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the application name in ArgoCD.
  name: keda
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  namespace: argocd
  # Annotations configuring sync sequence priority.
  annotations:
    # Human-readable explanation of this component's purpose.
    kubernetes.io/description: "Installs KEDA (Kubernetes Event-driven Autoscaling) controller"
    # Wave 1 installs KEDA operator before scaled objects are deployed in wave 4.
    argocd.argoproj.io/sync-wave: "1"
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the registry hosting the chart.
  source:
    # Official KEDA Helm chart registry URL.
    repoURL: https://kedacore.github.io/charts
    # The target chart to install.
    chart: keda
    # Pin version for stability.
    targetRevision: "2.20.1"
    # Helm parameters overriding the chart defaults.
    helm:
      parameters:
        # Enables validation webhooks.
        - name: webhooks.enabled
          value: "true"
        # Service Account name for KEDA operator.
        - name: serviceAccount.name
          value: "keda-operator"
  # Destination where manifests are deployed in EKS.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # Deploys operator in dedicated keda namespace.
    namespace: keda
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Extra sync configuration parameters.
    syncOptions:
      # Creates target namespace if it does not already exist.
      - CreateNamespace=true
      # Uses server side apply to prevent resource length validation errors.
      - ServerSideApply=true
```

### istiod.yaml

The istiod manifest deploys Istio daemon control plane.

Here is the annotated version of `istiod.yaml` showing detailed comments:

```yaml
# Targets the stable custom resource API for ArgoCD Application definitions.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the application name in ArgoCD.
  name: istiod
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  namespace: argocd
  # Annotations configuring sync sequence priority.
  annotations:
    # Human-readable explanation of this component's purpose.
    kubernetes.io/description: "Installs the Istio control plane (Daemon) for service mesh operations"
    # Wave 1 installs daemon after base CRDs are registered in wave 0.
    argocd.argoproj.io/sync-wave: "1"
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the registry hosting the chart.
  source:
    # Official Istio Helm registry.
    repoURL: https://istio-release.storage.googleapis.com/charts
    # The target chart to install.
    chart: istiod
    # Pin version for stability. Must match istio-base.yaml.
    targetRevision: "1.30.1"
    # Helm parameters overriding the chart defaults.
    helm:
      parameters:
        # Enables sidecar proxy injection automatically.
        - name: global.proxy.autoInject
          value: "enabled"
        # Disables mesh tracing to reduce overhead.
        - name: meshConfig.enableTracing
          value: "false"
        # Outputs access logs to stdout for collector.
        - name: meshConfig.accessLogFile
          value: "/dev/stdout"
  # Destination where manifests are deployed in EKS.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # Deploys in istio-system control namespace.
    namespace: istio-system
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Extra sync configuration parameters.
    syncOptions:
      # Namespace is already created in istio-base.yaml.
      - CreateNamespace=false
      # Uses server side apply to prevent resource length validation errors.
      - ServerSideApply=true
```

### karpenter-config.yaml

The karpenter-config manifest deploys node provisioning settings.

Here is the annotated version of `karpenter-config.yaml` showing detailed comments:

```yaml
# Targets the stable custom resource API for ArgoCD Application definitions.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the application name in ArgoCD.
  name: karpenter-config
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  namespace: argocd
  # Annotations configuring sync sequence priority.
  annotations:
    # Human-readable explanation of this component's purpose.
    kubernetes.io/description: "Deploys Karpenter autoscaler node classes and node pools"
    # Wave 2 configures node class definitions after Karpenter controller is active.
    argocd.argoproj.io/sync-wave: "2"
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the local directory.
  source:
    # Local Git repository path, matching values.yaml.
    repoURL: {{ .Values.repoURL | quote }}
    # Follows HEAD commit.
    targetRevision: HEAD
    # Path inside local repository where configurations reside.
    path: k8s/karpenter-config
    # Helm parameters overriding the chart defaults.
    helm:
      parameters:
        # Passes the cluster name down to templates.
        - name: clusterName
          value: {{ .Values.clusterName | quote }}
  # Destination where manifests are deployed in EKS.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # Karpenter configs are globally scope but app SA/config is in kube-system.
    namespace: kube-system
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Extra sync configuration parameters.
    syncOptions:
      # Namespace is already created in base setup.
      - CreateNamespace=false
      # Uses server side apply to prevent resource length validation errors.
      - ServerSideApply=true
```

### prometheus.yaml

The prometheus manifest deploys EKS monitoring stack.

Here is the annotated version of `prometheus.yaml` showing detailed comments:

```yaml
# Targets the stable custom resource API for ArgoCD Application definitions.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the application name in ArgoCD.
  name: prometheus
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  namespace: argocd
  # Annotations configuring sync sequence priority.
  annotations:
    # Human-readable explanation of this component's purpose.
    kubernetes.io/description: "Installs the Prometheus and Grafana monitoring stack (kube-prometheus-stack)"
    # Wave 3 installs monitoring before application workloads deploy in wave 4.
    argocd.argoproj.io/sync-wave: "3"
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the registry hosting the chart.
  source:
    # Official Prometheus community Helm charts registry URL.
    repoURL: https://prometheus-community.github.io/helm-charts
    # The target chart to install.
    chart: kube-prometheus-stack
    # Pin version for stability.
    targetRevision: "86.2.2"
    # Helm parameters overriding the chart defaults.
    helm:
      parameters:
        # Disables storage provisioner overrides.
        - name: prometheus.prometheusSpec.storageSpec
          value: ""
        # Sets default administration login password for Grafana.
        - name: grafana.adminPassword
          value: "changeme"
        # Enables dashboard discovery sidecars.
        - name: grafana.sidecar.dashboards.enabled
          value: "true"
        # Dashboard label that Grafana checks to load dashboards.
        # Must match dashboard definitions label.
        - name: grafana.sidecar.dashboards.label
          value: "grafana_dashboard"
        # Namespaces scanned by sidecar dashboard controller.
        - name: grafana.sidecar.dashboards.searchNamespace
          value: "ALL"
        # Dashboard folders group annotation.
        - name: grafana.sidecar.dashboards.folderAnnotation
          value: "grafana_folder"
        # Instructs Prometheus Operator to scan all namespaces for PodMonitors.
        - name: prometheus.prometheusSpec.podMonitorNamespaceSelector
          value: "{}"
        # Instructs Prometheus Operator to scan all namespaces for ServiceMonitors.
        - name: prometheus.prometheusSpec.serviceMonitorNamespaceSelector
          value: "{}"
  # Destination where manifests are deployed in EKS.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # Deploys in dedicated monitoring namespace.
    namespace: monitoring
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Extra sync configuration parameters.
    syncOptions:
      # Creates target namespace if it does not already exist.
      - CreateNamespace=true
      # Uses server side apply to prevent resource length validation errors.
      - ServerSideApply=true
```

### fastapi.yaml

The fastapi application deployment manager manifest.

Here is the annotated version of `fastapi.yaml` showing detailed comments:

```yaml
# Targets the stable custom resource API for ArgoCD Application definitions.
apiVersion: argoproj.io/v1alpha1
# Specifies that this resource is an ArgoCD Application.
kind: Application
# Metadata properties identifying this resource.
metadata:
  # The name defines the application name in ArgoCD.
  name: fastapi-app
  # Deploys this manifest in the namespace where the ArgoCD controller is running.
  namespace: argocd
  # Annotations configuring sync sequence priority.
  annotations:
    # Human-readable explanation of this component's purpose.
    kubernetes.io/description: "Deploys the zone-aware FastAPI application with metrics-based dynamic autoscaling"
    # Sync wave 4 installs the application layer after monitoring, secrets and network policies are ready.
    argocd.argoproj.io/sync-wave: "4"
  # Specifies deletion finalizers to clean up resources from EKS when deleted.
  finalizers:
    - resources-finalizer.argocd.argoproj.io
# Specific configuration details for the application deployment.
spec:
  # Maps this application to default project security settings.
  project: default
  # Source properties pointing to the local directory.
  source:
    # Local Git repository path, matching values.yaml.
    repoURL: {{ .Values.repoURL | quote }}
    # Follows HEAD commit.
    targetRevision: HEAD
    # Path inside local repository where configurations reside.
    path: k8s/fastapi
    # Helm parameters overriding the chart defaults.
    helm:
      parameters:
        # Passes the AWS region down to templates.
        - name: awsRegion
          value: {{ .Values.awsRegion | quote }}
  # Destination where manifests are deployed in EKS.
  destination:
    # Target server URL for the EKS local API gateway.
    server: https://kubernetes.default.svc
    # Deploys application in dedicated fastapi namespace.
    namespace: fastapi
  # Sync settings dictating how the controller aligns cluster state.
  syncPolicy:
    # Automatically synchronizes changes.
    automated:
      # Automatically deletes orphaned resource workloads from EKS.
      prune: true
      # Restores cluster state on manual drift or direct edits.
      selfHeal: true
    # Extra sync configuration parameters.
    syncOptions:
      # Creates target namespace if it does not already exist.
      - CreateNamespace=true
      # Uses server side apply to prevent resource length validation errors.
      - ServerSideApply=true
```

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
