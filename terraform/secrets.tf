
resource "aws_secretsmanager_secret" "google_api_key" {
  name        = "${local.cluster_name}/GOOGLE_API_KEY"
  description = "Google API Key for the FastAPI application"

  recovery_window_in_days = 7

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "google_api_key" {
  secret_id     = aws_secretsmanager_secret.google_api_key.id
  secret_string = jsonencode({
    GOOGLE_API_KEY = var.secret_value
  })
}
