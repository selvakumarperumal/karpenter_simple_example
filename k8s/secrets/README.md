# k8s/secrets/ — External Secrets (AWS Secrets Manager → K8s Secrets)

Applied by ArgoCD as the `app-secrets` Application at **sync wave 1**. Configures ESO to read from AWS Secrets Manager and create Kubernetes Secrets in the `fastapi` namespace.

---

## End-to-End Secret Flow

```mermaid
sequenceDiagram
    participant DEV as Developer / Ops
    participant TF as Terraform
    participant SM as AWS Secrets Manager
    participant ESO as External Secrets Operator
    participant K8S as K8s Secret (fastapi namespace)
    participant POD as FastAPI Pod

    TF->>SM: Create secret resource karpenter-demo/GOOGLE_API_KEY (empty)
    DEV->>SM: aws secretsmanager put-secret-value --secret-string "real-key"

    ESO->>SM: GetSecretValue karpenter-demo/GOOGLE_API_KEY (every 1h)
    SM-->>ESO: "real-key"
    ESO->>K8S: Create/Update Secret google-api-key in namespace fastapi
    Note over K8S: data.GOOGLE_API_KEY = base64("real-key")

    POD->>K8S: Read env var GOOGLE_API_KEY via secretKeyRef
    K8S-->>POD: "real-key"
```

---

## Files

| File | Kind | Scope | Description |
|---|---|---|---|
| `kustomization.yaml` | Kustomize | — | Lists resources to apply |
| `cluster-secret-store.yaml` | ClusterSecretStore | Cluster-wide | Configures ESO to connect to AWS Secrets Manager |
| `google-api-key.yaml` | ExternalSecret | Namespace: fastapi | Syncs GOOGLE_API_KEY into a K8s Secret |

---

## `kustomization.yaml` — Line-by-Line

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - cluster-secret-store.yaml
  # ClusterSecretStore is cluster-scoped (no namespace).
  # Must be applied BEFORE any ExternalSecret that references it.
  # ArgoCD applies resources in order, so listing it first is correct.

  - google-api-key.yaml
  # ExternalSecret in namespace fastapi.
  # ESO processes this after the ClusterSecretStore is ready.
```

---

## `cluster-secret-store.yaml` — Line-by-Line

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore          # Cluster-scoped: ExternalSecrets in ANY namespace can use this
metadata:
  name: aws-secrets-manager       # Referenced by ExternalSecret.spec.secretStoreRef.name

spec:
  provider:
    aws:
      service: SecretsManager     # Use AWS Secrets Manager (not SSM Parameter Store)
      region: us-east-1           # Must match the region where secrets were created in Terraform
      # Authentication: ESO uses the IRSA annotation on its ServiceAccount.
      # No explicit auth block needed here — ESO's pod picks up AWS credentials
      # from the mounted token via the annotation:
      #   eks.amazonaws.com/role-arn = arn:aws:iam::ACCOUNT:role/external-secrets-karpenter-demo
      # This is set by Terraform in iam-external-secrets.tf.
```

**ClusterSecretStore vs SecretStore:**

| Kind | Scope | Who can reference it |
|---|---|---|
| `ClusterSecretStore` | Cluster-wide | ExternalSecrets in ANY namespace |
| `SecretStore` | Namespace | Only ExternalSecrets in the SAME namespace |

Use `ClusterSecretStore` when multiple namespaces need to access the same AWS account/region.

---

## `google-api-key.yaml` — Line-by-Line

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: google-api-key
  namespace: fastapi              # The K8s Secret is created in THIS namespace
  # ESO creates the target Secret in the SAME namespace as the ExternalSecret.

spec:
  refreshInterval: 1h
  # ESO polls AWS Secrets Manager every hour.
  # If the secret value changes in AWS, ESO updates the K8s Secret within 1 hour.
  # For faster updates, reduce this (e.g. "5m"). Note: more AWS API calls = slightly more cost.

  secretStoreRef:
    name: aws-secrets-manager     # References cluster-secret-store.yaml above
    kind: ClusterSecretStore      # Must match the kind of the store

  target:
    name: google-api-key          # The name of the K8s Secret ESO creates
    creationPolicy: Owner
    # Owner: ESO owns the Secret lifecycle.
    #   - If this ExternalSecret is deleted, ESO also deletes the K8s Secret.
    #   - Use "Orphan" if you want the K8s Secret to survive ExternalSecret deletion.

  data:
    - secretKey: GOOGLE_API_KEY
      # Key inside the K8s Secret. The FastAPI deployment reads:
      #   env.valueFrom.secretKeyRef.key: GOOGLE_API_KEY

      remoteRef:
        key: karpenter-demo/GOOGLE_API_KEY
        # AWS Secrets Manager secret name.
        # Matches aws_secretsmanager_secret.google_api_key.name in terraform/secrets.tf
        # Convention: <cluster_name>/<SECRET_NAME>
        # The IAM policy in iam-external-secrets.tf allows:
        #   secretsmanager:GetSecretValue on arn:...:secret:karpenter-demo/*
```

---

## How the K8s Secret Looks After ESO Syncs

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: google-api-key
  namespace: fastapi
  # ESO also adds ownerReferences pointing to the ExternalSecret
type: Opaque
data:
  GOOGLE_API_KEY: eW91ci1hcGkta2V5    # base64("your-api-key")
```

The FastAPI pod reads it:
```yaml
env:
  - name: GOOGLE_API_KEY
    valueFrom:
      secretKeyRef:
        name: google-api-key    # K8s Secret name
        key: GOOGLE_API_KEY     # Key inside the Secret
```

---

## Adding More Secrets

To add a new secret (e.g. `DATABASE_URL`):

1. **Terraform** — add to `secrets.tf`:
```hcl
resource "aws_secretsmanager_secret" "database_url" {
  name = "karpenter-demo/DATABASE_URL"
}
```

2. **Set the value:**
```bash
aws secretsmanager put-secret-value \
  --secret-id karpenter-demo/DATABASE_URL \
  --secret-string "postgresql://user:pass@host:5432/db"
```

3. **Add to `google-api-key.yaml`** (or create a new ExternalSecret file):
```yaml
  data:
    - secretKey: GOOGLE_API_KEY
      remoteRef:
        key: karpenter-demo/GOOGLE_API_KEY
    - secretKey: DATABASE_URL         # add this block
      remoteRef:
        key: karpenter-demo/DATABASE_URL
```

4. **Mount in deployment:**
```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: google-api-key
        key: DATABASE_URL
```

---

## Verify ESO is Syncing

```bash
# Check ExternalSecret status
kubectl get externalsecret -n fastapi
# NAME             STORE                  REFRESH INTERVAL   STATUS         READY
# google-api-key   aws-secrets-manager    1h                 SecretSynced   True

# Check the K8s Secret was created
kubectl get secret google-api-key -n fastapi
# NAME             TYPE     DATA   AGE
# google-api-key   Opaque   1      5m

# Verify the key is present (value is base64-encoded)
kubectl get secret google-api-key -n fastapi -o jsonpath='{.data.GOOGLE_API_KEY}' | base64 -d

# ESO controller logs (if sync is failing)
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=30
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `STATUS: SecretSyncedError` | IAM permission denied | Check ESO IAM policy allows the secret ARN |
| `STATUS: SecretSyncedError` | Secret doesn't exist in AWS | Run `aws secretsmanager list-secrets` to verify |
| K8s Secret not in `fastapi` namespace | Wrong namespace in ExternalSecret | Check `metadata.namespace: fastapi` in `google-api-key.yaml` |
| ClusterSecretStore `Invalid` | Wrong region | Check `region: us-east-1` matches where the secret was created |
| Pod `CreateContainerConfigError` | K8s Secret doesn't exist yet | ESO may still be syncing; check `kubectl get externalsecret -n fastapi` |
