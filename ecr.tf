resource "aws_ecr_repository" "chareli_server" {
  name                 = "${var.app_name_prefix}-server-${var.environment}-${var.infra_suffix}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "backup_tool" {
  name                 = "${var.app_name_prefix}-backup-tool-${var.environment}-${var.infra_suffix}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}
output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.chareli_server.repository_url
}
