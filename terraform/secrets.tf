# ── Application Secrets — AWS Secrets Manager ─────────────────────────────────
#
# PURPOSE:
#   Creates secret placeholders in AWS Secrets Manager. Terraform manages the
#   secret resource (name, policy, rotation config) but NOT the secret value.
#   Values are set manually via AWS Console or CLI after `terraform apply`.
#
# AFTER APPLY — set the secret value:
#   aws secretsmanager put-secret-value \
#     --secret-id karpenter-demo/GOOGLE_API_KEY \
#     --secret-string "your-actual-api-key-here"
#
# CONSUMED BY:
#   k8s/secrets/google-api-key.yaml (ExternalSecret)
#   → ESO reads the value → creates K8s Secret "google-api-key" in namespace "fastapi"
#   → k8s/fastapi/deployment.yaml mounts it as env var GOOGLE_API_KEY
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "google_api_key" {
  name        = "${local.cluster_name}/GOOGLE_API_KEY"
  description = "Google API Key for the FastAPI application"

  # Prevent accidental deletion of a secret that apps depend on
  recovery_window_in_days = 7

  tags = local.tags
}
