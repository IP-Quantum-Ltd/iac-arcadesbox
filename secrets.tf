resource "aws_secretsmanager_secret" "application_secrets" {
  name        = "${var.app_name_prefix}/${var.environment}/${var.infra_suffix}/application-secrets"
  description = "Consolidated secrets for the Chareli application (${var.environment}-${var.infra_suffix})"
}

resource "null_resource" "upload_env_to_secret" {
  triggers = {
    env_file_hash = filemd5("${path.root}/.env")
  }

  depends_on = [aws_secretsmanager_secret.application_secrets]


  provisioner "local-exec" {
    # command = <<EOT
    #   ./scripts/upload-secrets.sh .env ${aws_secretsmanager_secret.application_secrets.name} ${var.aws_region}
    # EOT

    command = "./scripts/upload-secrets.sh '${path.root}/.env' '${aws_secretsmanager_secret.application_secrets.name}' '${var.aws_region}'"
  }
}

output "application_secrets_arn" {
  description = "ARN of the consolidated application secrets"
  value       = aws_secretsmanager_secret.application_secrets.arn
}
