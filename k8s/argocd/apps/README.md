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

The `apiVersion: v2` field declares this chart is compatible with Helm 3.x specifications. If set to `v1`, Helm will reject packaging configurations.

The `name: argocd-apps` field specifies the name of this chart.

The `version: 1.0.0` field tracks the version of the chart.

### values.yaml

The `repoURL: ""` variable defines the Git repository URL. It defaults to empty and is overridden by parameters from the root application. If wrong, child applications will fail to pull templates.

The `clusterName: ""` variable defines EKS cluster name metadata. It is used to tag subnets dynamically (matches `cluster_name` in [variables.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/variables.tf#L24)).

The `awsRegion: ""` variable defines target region. It matches `aws_region` in [variables.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/variables.tf#L18).

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
