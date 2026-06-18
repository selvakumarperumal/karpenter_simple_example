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

The ClusterSecretStore configuration sets up cluster-wide access to AWS Secrets Manager.

Here is the annotated version of `cluster-secret-store.yaml` showing detailed comments:

```yaml
# Targets the stable external-secrets operator API group.
apiVersion: external-secrets.io/v1beta1
# Specifies that this resource is a ClusterSecretStore.
kind: ClusterSecretStore
# Metadata identifying this store.
metadata:
  # The unique name of this store. Referenced by ExternalSecret resources.
  name: aws-secrets-manager
  # Annotations explaining the resource's purpose.
  annotations:
    kubernetes.io/description: "Configures cluster-wide access for the External Secrets Operator to read secrets from AWS Secrets Manager"
# Technical specifications for connecting to the cloud provider.
spec:
  provider:
    # Specifies AWS Secrets Manager provider configurations.
    aws:
      # Sets target AWS service to SecretsManager.
      service: SecretsManager
      # Target AWS region hosting the secrets. Matches values.yaml.
      region: {{ .Values.awsRegion | quote }}
```

### google-api-key.yaml

The ExternalSecret mapping pulls the Google API key from AWS into EKS.

Here is the annotated version of `google-api-key.yaml` showing detailed comments:

```yaml
# Targets the stable external-secrets operator API group.
apiVersion: external-secrets.io/v1beta1
# Specifies that this resource is an ExternalSecret.
kind: ExternalSecret
# Metadata identifying the secret mapping.
metadata:
  # Unique name of the ExternalSecret.
  name: google-api-key
  # Must reside in the application namespace to generate the local secret.
  namespace: fastapi
  # Annotations explaining the resource's purpose.
  annotations:
    kubernetes.io/description: "Defines the mapping and sync parameters for pulling the GOOGLE_API_KEY secret from AWS into the fastapi namespace"
# Technical specifications for the secret synchronization.
spec:
  # Interval duration between AWS API checks for updated values.
  refreshInterval: 1h
  # References the ClusterSecretStore provider.
  secretStoreRef:
    # Must match the ClusterSecretStore name defined in cluster-secret-store.yaml.
    name: aws-secrets-manager
    kind: ClusterSecretStore
  # Target details for the resulting Kubernetes Secret.
  target:
    # Name of the generated Kubernetes Secret.
    # Must match the secret reference in deployment.yaml.
    name: google-api-key
    # Deletes the generated Kubernetes Secret when this ExternalSecret is deleted.
    creationPolicy: Owner
  # Data mapping keys from AWS Secrets Manager to Kubernetes Secret fields.
  data:
    # The key inside the generated Kubernetes Secret.
    # Must match the key mapped in deployment.yaml.
    - secretKey: GOOGLE_API_KEY
      remoteRef:
        # The remote secret key path in AWS Secrets Manager.
        # Must match the secret name created in terraform/secrets.tf.
        key: {{ printf "%s/GOOGLE_API_KEY" .Values.clusterName | quote }}
```

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
