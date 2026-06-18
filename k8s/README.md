# Kubernetes Configurations Folder

This folder owns the Kubernetes resource manifests, dynamic scaling configurations, secrets synchronizer configurations, and Helm charts for the applications stack. It configures the target cluster state applied via ArgoCD.

## Architecture

```
+-------------------------------------------------------+
|                     k8s/ Folder                       |
|                                                       |
|   +--------------+                 +---------------+  |
|   |    argocd/   | --------------> |  secrets/     |  |
|   +--------------+                 +---------------+  |
|          |                                 |          |
|          v                                 v          |
|   +--------------+                 +---------------+  |
|   | karpenter-   |                 |   fastapi/    |  |
|   |   config/    |                 |               |  |
|   +--------------+                 +---------------+  |
+-------------------------------------------------------+
```

| Component | Upstream Target | Downstream Target |
|:---|:---|:---|
| `argocd/` | GitHub Repository | EKS Cluster workloads |
| `secrets/` | AWS Secrets Manager | `fastapi/` pods |
| `karpenter-config/` | EKS node groups | EC2 instances |
| `fastapi/` | `secrets/` and ECR | Service endpoints |

## File-by-file explanation

### argocd

The `argocd/` directory contains the root application and application list configurations. If this folder is missing, ArgoCD cannot synchronize any child applications or infrastructure tools in the cluster.

### fastapi

The `fastapi/` directory holds the zone-aware FastAPI application Helm templates. If this folder is missing, the application workloads, services, and gateways cannot be deployed.

### karpenter-config

The `karpenter-config/` directory holds the Karpenter provisioning manifests. If this folder is missing, Karpenter will not know how to discover AWS resources or provision EC2 capacity.

### secrets

The `secrets/` directory holds the External Secrets configurations. If this folder is missing, pods will fail to retrieve credentials from AWS Secrets Manager.

## Versions and APIs used

| Component | Target Version | apiVersion Group |
|:---|:---|:---|
| Kubernetes | 1.33+ | Standard groups |
| Helm | 3.17+ | v2 |
| Karpenter | v1.11+ | `karpenter.sh/v1` and `karpenter.k8s.aws/v1` |
| KEDA | 2.20+ | `keda.sh/v1alpha1` |
| Istio | 1.29+ | `gateway.networking.k8s.io/v1` |

## Prerequisites

| Dependency | Required State | Location |
|:---|:---|:---|
| EKS Cluster | Provisioned and active | AWS |
| ArgoCD | Installed in cluster | Namespace `argocd` |
| kubectl | Configured locally | local shell |

## Commands

We render the Helm templates locally to verify that all variables parse correctly before committing changes.
```bash
helm template k8s/fastapi
```

We render the Karpenter config manifests to verify node provisioning variables.
```bash
helm template k8s/karpenter-config
```

We test the secrets mapping templates to verify secrets parameters.
```bash
helm template k8s/secrets
```

## Troubleshooting

We resolve validation errors during apply by verifying that the Gateway API CRDs and operator CRDs are installed before template files are parsed.

We resolve namespace creation errors by ensuring that namespaces are declared in sync wave 0 or managed by ArgoCD namespaces auto-creation settings.

We resolve image lookup errors by verifying that the image repository parameter inside values file matches the ECR registry URI.

## References

| Tool | Official Documentation |
|:---|:---|
| Kubernetes | [Kubernetes docs](https://kubernetes.io/docs/home/) |
| Helm | [Helm docs](https://helm.sh/docs/) |
