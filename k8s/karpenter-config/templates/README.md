# Karpenter Capacity Templates Folder

This folder owns the Karpenter custom resource templates. These templates specify how worker nodes are provisioned in AWS, detailing instance constraints, disk mappings, and network discovery tags.

## Architecture

```
+-------------------------------------------------------------+
|                     templates/ Folder                       |
|                                                             |
|   +-------------------+              +-------------------+  |
|   |   nodepool.yaml   | -----------> |  ec2nodeclass.tf  |  |
|   +-------------------+              +-------------------+  |
|                                                |            |
|                                                v            |
|                                      +-------------------+  |
|                                      |   AWS Subnet/SG   |  |
|                                      +-------------------+  |
+-------------------------------------------------------------+
```

| Manifest File | Kind | Upstream Dependency | Downstream Target |
|:---|:---|:---|:---|
| `nodepool.yaml` | `NodePool` | `ec2nodeclass.yaml` | Node scheduling rules |
| `ec2nodeclass.yaml` | `EC2NodeClass` | `values.yaml` | AWS EC2 Node specs |

## File-by-file explanation

### ec2nodeclass.yaml

The `apiVersion: karpenter.k8s.aws/v1` field targets the stable AWS Karpenter provider API group. Any manifest still using `v1beta1` will fail CRD validation on clusters running Karpenter v1.1 or later.

The `kind: EC2NodeClass` field specifies that this resource is an EC2NodeClass configuration template.

The `spec.amiFamily: AL2023` field specifies Amazon Linux 2023 optimization for worker nodes.

The `spec.amiSelectorTerms` block selects target AMIs.
The `alias: al2023@latest` parameter auto-discovers the latest EKS-optimized AL2023 AMI. Required in Karpenter v1 API. If omitted, the NodeClass fails validation.

The `spec.role: "karpenter-node-role"` field specifies the IAM Instance Profile role name. It must match `node_iam_role_name` in [iam-karpenter.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/iam-karpenter.tf#L54). If wrong, EC2 nodes launch but fail to join the cluster.

The `spec.subnetSelectorTerms` block declares subnet discovery tags.
The `karpenter.sh/discovery: {{ .Values.clusterName }}` parameter finds private subnets (configured in [vpc.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/vpc.tf#L57)).

The `spec.securityGroupSelectorTerms` block declares security group discovery tags.
The `karpenter.sh/discovery: {{ .Values.clusterName }}` parameter finds security groups (configured in [eks.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/eks.tf#L114)). If wrong, nodes launch with default security groups, blocking inter-pod communication.

The `spec.blockDeviceMappings` block configures root disks.
The `deviceName: /dev/xvda` parameter sets root path.
The `ebs` block configures volume parameters.
The `volumeSize: 50Gi` parameter sets disk size.
The `volumeType: gp3` parameter sets disk type.
The `encrypted: true` parameter configures volume encryption.

The `spec.tags` block defines tags applied to provisioned EC2 instances.
The `Environment: production` field configures env tag.
The `ManagedBy: Karpenter` field configures ownership tag.
The `Cluster: {{ .Values.clusterName }}` field configures EKS association tag.

### nodepool.yaml

The `apiVersion: karpenter.sh/v1` and `kind: NodePool` fields target the core custom resource schema.

The `spec.template.metadata.labels.role: application` label assigns tags to launched instances, matching pod affinity rules.

The `spec.template.spec.nodeClassRef` block references the NodeClass.
The `group: karpenter.k8s.aws`, `kind: EC2NodeClass`, and `name: default` parameters bind this NodePool to our AWS configuration.

The `spec.template.spec.requirements` list declares instance constraints.
The `karpenter.sh/capacity-type` requirement allows Spot and On-Demand (`["on-demand", "spot"]`).
The `kubernetes.io/arch` requirement filters architecture to `amd64`.
The `karpenter.k8s.aws/instance-category` requirement allows compute, memory, and general purpose nodes (`["c", "m", "r"]`).
The `karpenter.k8s.aws/instance-generation` requirement excludes older instances (`operator: Gt`, `values: ["2"]`).
The `karpenter.k8s.aws/instance-size` requirement excludes burstable small instances (`operator: NotIn`, `values: ["nano", "micro", "small", "metal"]`) to optimize scheduling densities.

The `spec.limits` block overrides CPU and memory boundaries (cpu: `"100"`, memory: `400Gi`) to control max billing rates.

The `spec.disruption` block configures node consolidation policies.
The `consolidationPolicy: WhenEmptyOrUnderutilized` consolidation policy terminates empty or low-load nodes. Consolidated from `WhenUnderutilized` in v1 API.
The `consolidateAfter: 1m` configuration sets execution delay.

## Versions and APIs used

| Component | Target Version | apiVersion Group |
|:---|:---|:---|
| NodePool | v1 | `karpenter.sh/v1` |
| EC2NodeClass | v1 | `karpenter.k8s.aws/v1` |

## Prerequisites

| Requirement | Target Configuration | Location |
|:---|:---|:---|
| Karpenter Controller | Deployed and active | Namespace `kube-system` |

## Commands

We render the templates locally using mock parameter overrides to verify chart syntax.
```bash
helm template k8s/karpenter-config
```

We apply the manifests using ArgoCD sync triggers.
```bash
kubectl apply -f k8s/karpenter-config/templates/
```

## Troubleshooting

We resolve subnet mapping errors by verifying that private subnets in AWS include matching tags for Karpenter discovery.

We resolve registration timeouts by checking that the EC2NodeClass role name matches EKS node role.

## References

| Tool | Official Documentation |
|:---|:---|
| Karpenter Scheduling | [Karpenter concepts](https://karpenter.sh/docs/concepts/) |
