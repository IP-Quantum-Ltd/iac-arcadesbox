resource "aws_secretsmanager_secret" "application_secrets" {
  name        = "${var.app_name_prefix}/${var.environment}/${var.infra_suffix}/application-secrets"
  description = "Consolidated secrets for the ArcadesBox application (${var.environment}-${var.infra_suffix})"
}

resource "aws_secretsmanager_secret" "backup_tool_secrets" {
  name        = "${var.app_name_prefix}/${var.environment}/${var.infra_suffix}/backup-tool-secrets"
  description = "Consolidated secrets for the ArcadesBox storage backup tool (${var.environment}-${var.infra_suffix})"

}

# Secret values are managed manually via AWS CLI/Console.
# Terraform only provisions the secret shell (name + ARN).
# Use scripts/upload-secrets.sh independently to populate values.

output "application_secrets_arn" {
  description = "ARN of the consolidated application secrets"
  value       = aws_secretsmanager_secret.application_secrets.arn
}

output "backup_tool_secrets_arn" {
  description = "ARN of the consolidated application secrets"
  value       = aws_secretsmanager_secret.backup_tool_secrets.arn
}
