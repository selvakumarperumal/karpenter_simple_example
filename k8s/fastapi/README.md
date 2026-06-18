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

The `apiVersion: v2` field declares this chart is compatible with Helm 3.x specifications. If set to `v1`, Helm will reject packaging configurations.

The `name: fastapi-app` field specifies the name of this chart.

The `version: 1.0.0` field tracks the version of the chart.

### values.yaml

The `awsRegion: "ap-south-1"` variable defines the target region. It matches `aws_region` in [variables.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/variables.tf#L18).

The `zones: ["a", "b", "c"]` array defines the availability zone suffixes. It renders separate deployments per zone, enforcing local traffic boundaries.

The `image.repository: ""` variable defines the target ECR registry repository URL. It defaults to empty and is overridden by the CI pipeline run (matches `ecr_repository_url` output inside [outputs.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/outputs.tf#L63)).

The `image.tag: "latest"` variable specifies the image version. It defaults to `latest` and is updated to the git commit SHA tag during CI runs.

The `image.pullPolicy: "Always"` field configures the image pull behavior. It ensures updated tags are fetched on container restart.

The `resources.requests.cpu: "100m"` field sets the guaranteed CPU allocation.
The `resources.requests.memory: "128Mi"` field sets the guaranteed memory allocation.
The `resources.limits.cpu: "200m"` field sets the maximum CPU limit.
The `resources.limits.memory: "256Mi"` field sets the maximum memory limit. If breached, the container is OOMKilled by EKS.

The `keda.minReplicas: 1` variable sets the minimum active pod count per zone.
The `keda.maxReplicas: 10` variable sets the maximum allowed pod count per zone.
The `keda.threshold: "10"` variable sets the scaling threshold of 10 requests per second per pod.

### .helmignore

The `templates/README.md` entry tells Helm to ignore the markdown documentation file during template rendering, avoiding syntax failures.

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
