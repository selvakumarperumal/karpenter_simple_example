# Secrets Sync Helm Chart

This folder owns the Helm chart configurations representing secret synchronization parameters. It configures the target cluster name and region settings.

## Architecture

```
+-------------------------------------------------------------+
|                     secrets/ Folder                         |
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
| `templates/` | `values.yaml` | secrets templates |

## File-by-file explanation

### Chart.yaml

The Helm chart metadata file defines the name, description, and API specification version.

Here is the annotated version of `Chart.yaml` showing detailed comments:

```yaml
# Specifies the Helm packaging API version. v2 is required for Helm 3.x.
apiVersion: v2
# Unique name identifying this secrets synchronizer Helm chart.
name: app-secrets
# Description of the purpose of this Helm chart.
description: A Helm chart for configuring ExternalSecrets and ClusterSecretStore
# Chart type, which is application rather than library.
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
# Target AWS region hosting all resources (EKS, ECR, VPC, etc.).
# Must align with aws_region inside terraform/variables.tf.
awsRegion: "ap-south-1"

# The name of the target EKS cluster, used for tagging and configuration discovery.
# Must align with cluster_name inside terraform/variables.tf.
clusterName: "karpenter-demo"
```

### .helmignore

The `.helmignore` configuration file tells Helm to ignore specific files in this directory context during deployment. The entry `templates/README.md` forces Helm to exclude the templates documentation from template parsing checks, preventing manifest generation failures.

## Versions and APIs used

| Component | Target Version | apiVersion Group |
|:---|:---|:---|
| Helm Chart | v2 | Helm 3.x specifications |

## Prerequisites

| Requirement | Target Configuration | Location |
|:---|:---|:---|
| Helm | `3.17+` installed | local shell |

## Commands

We render the Helm templates locally using mock parameter overrides to verify chart syntax.
```bash
helm template k8s/secrets --set clusterName="test-cluster" --set awsRegion="ap-south-1"
```

We run the Helm linter to check chart syntax.
```bash
helm lint k8s/secrets
```

## Troubleshooting

We resolve empty variables issues by verifying that values are correctly passed inside the parent charts parameters.

## References

| Tool | Official Documentation |
|:---|:---|
| Helm | [Helm docs](https://helm.sh/docs/) |
