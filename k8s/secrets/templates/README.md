# Secrets Mapping Resources Folder

This folder owns the Kubernetes resource templates that configure secret synchronization. It configures the link between the External Secrets Operator and AWS Secrets Manager.

## Architecture

```
+-------------------------------------------------------------+
|                     templates/ Folder                       |
|                                                             |
|   +---------------------+              +-----------------+  |
|   | google-api-key.yaml | -----------> | cluster-secret- |  |
|   |                     |              |    store.yaml   |  |
|   +---------------------+              +-----------------+  |
|                                                |            |
|                                                v            |
|                                      +-------------------+  |
|                                      | AWS Secrets Mgr   |  |
|                                      +-------------------+  |
+-------------------------------------------------------------+
```

| Manifest File | Kind | Upstream Dependency | Downstream Target |
|:---|:---|:---|:---|
| `google-api-key.yaml` | `ExternalSecret` | `cluster-secret-store.yaml` | Kubernetes Secret |
| `cluster-secret-store.yaml` | `ClusterSecretStore` | `values.yaml` | AWS API connections |

## File-by-file explanation

### cluster-secret-store.yaml

The `apiVersion: external-secrets.io/v1beta1` and `kind: ClusterSecretStore` fields declare a ClusterSecretStore custom resource. Any typo in these fields prevents the resources from being registered by the API server.

The `metadata.name: aws-secrets-manager` field specifies the name of this store. It is referenced by ExternalSecret resources.

The `spec.provider.aws.service: SecretsManager` field tells the operator to connect to AWS Secrets Manager endpoints. If changed, the operator will attempt to resolve Parameter Store paths instead.

The `spec.provider.aws.region: {{ .Values.awsRegion }}` variable configures the target AWS region (matches `awsRegion` parameter inside [values.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/secrets/values.yaml#L3)).

### google-api-key.yaml

The `apiVersion: external-secrets.io/v1beta1` and `kind: ExternalSecret` fields declare an ExternalSecret custom resource.

The `metadata.name: google-api-key` field defines the resource name.

The `metadata.namespace: fastapi` field targets deployment to the `fastapi` namespace.

The `spec.refreshInterval: 1h` field configures the operator to query AWS Secrets Manager every 1 hour to fetch updated secret values.

The `spec.secretStoreRef` block references the provider.
The `name: aws-secrets-manager` and `kind: ClusterSecretStore` parameters bind this mapping to our provider.

The `spec.target` block configures the resulting Kubernetes Secret.
The `name: google-api-key` parameter sets output name (matches mapping inside [deployment.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/fastapi/templates/deployment.yaml#L97)). If mismatched, pods will fail startup checks.
The `creationPolicy: Owner` option specifies that the operator will delete the generated Kubernetes Secret when the ExternalSecret is deleted.

The `spec.data` block defines keys.
The `secretKey: GOOGLE_API_KEY` parameter sets the key name inside the generated secret (matches target key inside [deployment.yaml](file:///home/selva/Documents/k8s/karpenter_simple_example/k8s/fastapi/templates/deployment.yaml#L98)).
The `remoteRef.key: {{ printf "%s/GOOGLE_API_KEY" .Values.clusterName | quote }}` parameter defines target remote key (matches secret path created in [secrets.tf](file:///home/selva/Documents/k8s/karpenter_simple_example/terraform/secrets.tf#L20)). If wrong, the operator fails to fetch keys.

## Versions and APIs used

| Component | Target Version | apiVersion Group |
|:---|:---|:---|
| ClusterSecretStore | v1beta1 | `external-secrets.io/v1beta1` |
| ExternalSecret | v1beta1 | `external-secrets.io/v1beta1` |

## Prerequisites

| Requirement | Target Configuration | Location |
|:---|:---|:---|
| External Secrets Controller | Deployed and active | Namespace `external-secrets` |

## Commands

We render the Helm templates locally to verify that variables parse correctly before committing changes.
```bash
helm template k8s/secrets
```

We apply the manifests using ArgoCD sync triggers.
```bash
kubectl apply -f k8s/secrets/templates/
```

## Troubleshooting

We resolve synchronization failures by checking that the IAM user keys assigned to the controller have read permissions for target Secrets Manager ARNs.

We resolve secret lookup errors by verifying that the secret exists in AWS Secrets Manager under name `${clusterName}/GOOGLE_API_KEY`.

## References

| Tool | Official Documentation |
|:---|:---|
| External Secrets Operator | [ESO docs](https://external-secrets.io/) |
| AWS Secrets Manager Provider | [ESO AWS Provider](https://external-secrets.io/latest/provider/aws-secrets-manager/) |
