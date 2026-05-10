resource "aws_ecr_repository" "ai_agent" {
  name                 = "${var.app_name_prefix}-ai-agent-${var.environment}-${var.infra_suffix}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keep the most recent 10 images; expire untagged after 7 days.
resource "aws_ecr_lifecycle_policy" "ai_agent" {
  repository = aws_ecr_repository.ai_agent.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the most recent 10 tagged images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

output "ai_agent_ecr_repository_url" {
  description = "The URL of the AI agent ECR repository."
  value       = aws_ecr_repository.ai_agent.repository_url
}
