# FastAPI Application Helm Chart

This folder owns the Helm chart configurations representing parameter values for the FastAPI workload. It defines zone overrides, replica counts, resources requests and limits, and autoscaling thresholds.

## Architecture

```
+-------------------------------------------------------------+
|                     fastapi/ Folder                         |
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
| `values.yaml` | `app-ci.yaml` | `templates/` templates |
| `templates/` | `values.yaml` | Kubernetes manifests |

## File-by-file explanation

### Chart.yaml

The Helm chart metadata file defines the name, description, and API specification version.

Here is the annotated version of `Chart.yaml` showing detailed comments:

```yaml
# Specifies the Helm packaging API version. v2 is required for Helm 3.x.
apiVersion: v2
# Unique name identifying this application Helm chart.
name: fastapi-app
# Description of the purpose of this Helm chart.
description: A Helm chart for deploying the FastAPI application with multi-zone support and metrics-based scaling
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

# Availability zone suffixes. Creates separate deployments per zone to enforce zone topology.
zones:
  - a
  - b
  - c

# Container image configurations.
image:
  # ECR registry repository URL where EKS pulls the application container.
  # Must match the repository created in terraform/ecr.tf.
  repository: "961445532924.dkr.ecr.ap-south-1.amazonaws.com/fastapi-app"
  # Container image tag, updated dynamically to git commit SHA during CI runs in app-ci.yaml.
  tag: "latest"
  # Configuration indicating when the kubelet should pull the image.
  pullPolicy: "Always"

# CPU and Memory resource configurations for container workloads.
resources:
  # Guaranteed resource boundaries requested by the container scheduler.
  requests:
    cpu: "250m"
    memory: "256Mi"
  # Maximum resource limits before container throttling or OOM termination.
  limits:
    cpu: "500m"
    memory: "512Mi"

# KEDA event-driven autoscaling parameters.
keda:
  # Minimum active replica counts per availability zone.
  minReplicas: 1
  # Maximum allowed scaling replica boundaries per availability zone.
  maxReplicas: 10
  # Target metric threshold of requests per second per pod to trigger scaling actions.
  threshold: "10"
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

We render the Helm templates locally to verify that variables parse correctly before committing changes.
```bash
helm template k8s/fastapi
```

We run the Helm linter to check chart syntax.
```bash
helm lint k8s/fastapi
```

## Troubleshooting

We resolve empty variables issues by verifying that values are correctly passed inside the parent charts parameters.

## References

| Tool | Official Documentation |
|:---|:---|
| Helm | [Helm docs](https://helm.sh/docs/) |
