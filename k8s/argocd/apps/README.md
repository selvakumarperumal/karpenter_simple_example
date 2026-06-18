# ArgoCD Applications Chart Reference

This folder owns the parent Helm chart that configures the individual child applications managed by ArgoCD. It handles variable pass-through (such as Git repository, EKS cluster name, and region parameters) to each template.

## Architecture

```
+-------------------------------------------------------------+
|                      apps/ Folder                           |
|                                                             |
|  +----------------+      +-------------------------------+  |
|  |   Chart.yaml   | ---> |          values.yaml          |  |
|  +----------------+      +-------------------------------+  |
|                                  |                          |
|                                  v                          |
|                          +-------------------------------+  |
|                          |          templates/           |  |
|                          +-------------------------------+  |
+-------------------------------------------------------------+
```

| Component | Upstream Dependency | Downstream Target |
|:---|:---|:---|
| `Chart.yaml` | None | Helm engine |
| `values.yaml` | `app-of-apps.yaml` | `templates/` templates |
| `templates/` | `values.yaml` | ArgoCD Application custom resources |

## File-by-file explanation

### Chart.yaml

The Helm chart metadata file defines the name, description, and API specification version.

Here is the annotated version of `Chart.yaml` showing detailed comments:

```yaml
# Specifies the Helm packaging version. apiVersion v2 is required for Helm 3.x.
apiVersion: v2
# Unique name identifying this parent Helm chart.
name: argocd-apps
# Simple description of the purpose of this Helm chart.
description: A parent Helm chart to deploy all ArgoCD child applications dynamically
# Defines the chart type, which is application rather than library.
type: application
# The chart version tracking changes made to these definitions.
version: 1.0.0
# The underlying application software version represented by this deployment.
appVersion: "1.0.0"
```

### values.yaml

The default configuration values file defines global parameters passed down to the application templates.

Here is the annotated version of `values.yaml` showing detailed comments:

```yaml
# Git repository URL where ArgoCD looks for source code and manifests templates.
# Must match the git repository URL created in GitHub.
repoURL: "https://github.com/selvakumarperumal/karpenter_simple_example.git"

# The name of the target EKS cluster, used for tagging and configuration discovery.
# Must align with cluster_name inside terraform/variables.tf.
clusterName: "karpenter-demo"

# Target AWS region hosting all resources (EKS, ECR, VPC, etc.).
# Must align with aws_region inside terraform/variables.tf.
awsRegion: "ap-south-1"
```

## Versions and APIs used

| Component | Target Version | apiVersion Group |
|:---|:---|:---|
| Helm Chart | v2 | Helm 3.x specifications |

## Prerequisites

| Requirement | Target Configuration | Location |
|:---|:---|:---|
| Helm | `3.17+` installed | local shell |

## Commands

We render the templates locally using mock parameter overrides to verify chart syntax.
```bash
helm template k8s/argocd/apps --set repoURL="https://github.com" --set clusterName="test" --set awsRegion="us-east-1"
```

We run the Helm linter to check values keys and format mappings.
```bash
helm lint k8s/argocd/apps
```

## Troubleshooting

We resolve empty variables issues by verifying that values are correctly passed inside `spec.source.helm.parameters` inside the root `app-of-apps.yaml` manifest.

We resolve lint errors by checking for incorrect spacing or indentation inside custom resources templates.

## References

| Tool | Official Documentation |
|:---|:---|
| Helm Charts | [Helm Topics: Charts](https://helm.sh/docs/topics/charts/) |
