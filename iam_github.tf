data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "github_oidc_role" {
  name = "${var.app_name_prefix}-${var.environment}-${var.infra_suffix}-github-oidc-role"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Federated" : data.aws_iam_openid_connect_provider.github.arn
          },
          "Action" : "sts:AssumeRoleWithWebIdentity",
          "Condition" : {
            "StringEquals" : {
              "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
            },
            "StringLike" : {
              "token.actions.githubusercontent.com:sub" : "repo:${var.github_org}/${var.github_repo}:*"
            }
          }
        }
      ]
  })

}

# -----------------------------------------------------------------------------
# IAM Policy Document for the GitHub Actions Role
# This defines the permissions the CI/CD pipeline needs.
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "github_oidc_policy_doc" {
  # --- ECR Permissions ---
  # Allows pushing the backend server image.
  statement {
    sid    = "ECRPushAccess"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:DescribeImages"
    ]
    # Dynamically reference the ECR repository ARN from ecr.tf
    resources = [
      aws_ecr_repository.chareli_server.arn,
      aws_ecr_repository.ai_agent.arn,
    ]
  }

  statement {
    sid       = "ECRLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # This action requires a wildcard resource.
  }

  # --- ECS Permissions ---
  # Allows deploying the new task definition to the service.
  statement {
    sid    = "ECSDeployAccess"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:UpdateService",
      "ecs:DescribeServices",
      "ecs:TagResource"

    ]
    resources = [
      # Grant permission to register any revision of our specific task definition family
      "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/${aws_ecs_task_definition.app.family}:*",
      "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:task-definition/${aws_ecs_task_definition.ai_agent.family}:*",
      # Grant permission to update our specific service in our specific cluster
      aws_ecs_service.app.id, # Service ARN is its ID in this context
      aws_ecs_service.ai_agent.id,
    ]
  }

  statement {
    sid       = "ECSDescribeTaskDefinitionWildcard"
    effect    = "Allow"
    actions   = ["ecs:DescribeTaskDefinition"]
    resources = ["*"] # Required — AWS does NOT support resource scoping here
  }

  # --- IAM PassRole Permission ---
  # CRITICAL: Allows the CI/CD pipeline to pass the task execution role to the ECS service.
  # This is required when a service is updated with a new task definition that has a role.
  statement {
    sid    = "ECSPassRoleAccess"
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    # Restrict PassRole to ONLY the roles that ECS tasks need to assume.
    resources = [
      aws_iam_role.ecs_task_execution.arn,
      aws_iam_role.ecs_task.arn,
      aws_iam_role.ai_agent_task_execution.arn,
      aws_iam_role.ai_agent_task.arn,
    ]
    # Add a condition to be extra secure, ensuring it's only passed to ECS
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

}

# -----------------------------------------------------------------------------
# IAM Policy Resource and Attachment
# -----------------------------------------------------------------------------
resource "aws_iam_policy" "github_oidc_role_policy" {
  name   = "${var.app_name_prefix}-${var.environment}-${var.infra_suffix}-github-oidc-policy"
  policy = data.aws_iam_policy_document.github_oidc_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "github_oidc_role_policy_attachment" {
  role       = aws_iam_role.github_oidc_role.name
  policy_arn = aws_iam_policy.github_oidc_role_policy.arn
}

# --- Output the ARN of the role for your GitHub Actions workflow ---
output "github_actions_role_arn" {
  description = "The ARN of the IAM role for GitHub Actions to assume."
  value       = aws_iam_role.github_oidc_role.arn
}
