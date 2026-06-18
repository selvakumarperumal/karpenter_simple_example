# Karpenter Node Config Chart

This folder owns the Helm chart configurations representing scaling configurations for Karpenter. It wraps parameters used to discover security groups and subnets dynamically.

## Architecture

```
+-------------------------------------------------------------+
|                 karpenter-config/ Folder                    |
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
| `templates/` | `values.yaml` | Karpenter custom resources |

## File-by-file explanation

### Chart.yaml

The `apiVersion: v2` field declares this chart is compatible with Helm 3.x specifications. If set to `v1`, Helm will reject packaging configurations.

The `name: karpenter-config` field specifies the name of this chart.

The `version: 1.0.0` field tracks the version of the chart.

### values.yaml

The `clusterName: "karpenter-demo"` variable defines the target cluster name. It is passed to templates to build tag lookups. Must match `cluster_name` inside [variables.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/variables.tf#L24). If wrong, Karpenter subnet and security group discovery selectors fail to locate any resources.

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

We render the Helm templates locally using mock parameter overrides to verify chart syntax.
```bash
helm template k8s/karpenter-config --set clusterName="test-cluster"
```

We run the Helm linter to check chart syntax.
```bash
helm lint k8s/karpenter-config
```

## Troubleshooting

We resolve empty variables issues by verifying that values are correctly passed inside the parent charts parameters.

## References

| Tool | Official Documentation |
|:---|:---|
| Helm | [Helm docs](https://helm.sh/docs/) |
