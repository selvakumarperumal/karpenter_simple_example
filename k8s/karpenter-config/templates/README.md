# Karpenter Capacity Templates Folder

This folder owns the Karpenter custom resource templates. These templates specify how worker nodes are provisioned in AWS, detailing instance constraints, disk mappings, and network discovery tags.

## Architecture

```
+-------------------------------------------------------------+
|                     templates/ Folder                       |
|                                                             |
|   +-------------------+              +-------------------+  |
|   |   nodepool.yaml   | -----------> |  ec2nodeclass.yaml |  |
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

The EC2NodeClass template configures AWS-specific instance settings.

Here is the annotated version of `ec2nodeclass.yaml` showing detailed comments:

```yaml
# Targets the stable AWS Karpenter provider API group.
# Must use v1 API group for Karpenter v1.x+.
apiVersion: karpenter.k8s.aws/v1
# Specifies that this resource is an EC2NodeClass configuration template.
kind: EC2NodeClass
# Metadata properties identifying this resource.
metadata:
  # The name of this NodeClass. NodePools reference this name in nodeClassRef.name.
  name: default
  # Annotations explaining the resource.
  annotations:
    kubernetes.io/description: "Defines AWS-specific configuration for EC2 instances launched by Karpenter"
# Technical specifications for AWS-specific configurations.
spec:
  # The default OS and architecture family. AL2023 optimizes worker nodes.
  amiFamily: AL2023

  # AMI selection queries. Karpenter uses this to select AMIs for provisioned instances.
  amiSelectorTerms:
    # Auto-discovers the latest EKS-optimized AL2023 AMI.
    - alias: al2023@latest

  # The IAM Instance Profile role name.
  # Must match node_iam_role_name in terraform/iam-karpenter.tf.
  # If wrong, EC2 nodes launch but fail to join the cluster.
  role: "karpenter-node-role"

  # Subnet selector terms. Karpenter uses this to locate target subnets.
  subnetSelectorTerms:
    - tags:
        # Discovers private subnets tagged with the cluster name.
        # Must match EKS subnet tags configured in terraform/vpc.tf.
        karpenter.sh/discovery: {{ .Values.clusterName | quote }}

  # Security group selector terms. Karpenter uses this to locate target security groups.
  securityGroupSelectorTerms:
    - tags:
        # Discovers security groups tagged with the cluster name.
        # Must match EKS security group tags configured in terraform/eks.tf.
        # If wrong, nodes launch with default security groups, blocking inter-pod communication.
        karpenter.sh/discovery: {{ .Values.clusterName | quote }}

  # EBS block device mappings.
  blockDeviceMappings:
    # Specifies the root disk device path.
    - deviceName: /dev/xvda
      ebs:
        # Root volume storage size.
        volumeSize: 50Gi
        # High performance gp3 storage volume type.
        volumeType: gp3
        # Mandatory storage volume encryption.
        encrypted: true

  # Custom AWS tags applied to EC2 instances launched by Karpenter.
  tags:
    Environment: production
    ManagedBy: Karpenter
    Cluster: {{ .Values.clusterName | quote }}
```

### nodepool.yaml

The NodePool template configures scheduling, resource limits, and disruption policies.

Here is the annotated version of `nodepool.yaml` showing detailed comments:

```yaml
# Targets the core Karpenter scheduling API group.
# Must use v1 API group for Karpenter v1.x+.
apiVersion: karpenter.sh/v1
# Specifies that this resource is a NodePool.
kind: NodePool
# Metadata properties identifying this resource.
metadata:
  # Unique NodePool name.
  name: default
  # Annotations explaining the resource.
  annotations:
    kubernetes.io/description: "Defines the scheduling and sizing rules for instances Karpenter provisions for app pods"
# Technical specifications for node provisioning and scheduling.
spec:
  # Templates for resources Karpenter provisions.
  template:
    metadata:
      # Labels applied to all provisioned worker nodes.
      labels:
        role: application
    spec:
      # References the EC2NodeClass defining the cloud provider settings.
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        # Binds this NodePool to the default EC2NodeClass defined in ec2nodeclass.yaml.
        name: default

      # Requirements constraints that Karpenter evaluates to select instance types.
      requirements:
        # Allows spot and on-demand capacity.
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]

        # Restricts architecture to amd64.
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]

        # Restricts instance category to compute, memory, and general purpose nodes.
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]

        # Restricts instance generation to Gt (Greater than) 2.
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]

        # Excludes small or burstable instance sizes to optimize scheduling densities.
        - key: karpenter.k8s.aws/instance-size
          operator: NotIn
          values: ["nano", "micro", "small", "metal"]

  # Limits max resources that can be provisioned by this NodePool.
  # Controls cloud provider billing rates.
  limits:
    cpu: "100"
    memory: 400Gi

  # Disruption settings control node termination and consolidation.
  disruption:
    # Scale down policy. WhenEmptyOrUnderutilized terminates empty or low-load nodes.
    consolidationPolicy: WhenEmptyOrUnderutilized
    # Delay duration before consolidation triggers.
    consolidateAfter: 1m
```

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
