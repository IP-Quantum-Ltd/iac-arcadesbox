# -----------------------------------------------------------------------------
# IAM Role for Terraform CI/CD Pipeline (GitHub Actions)
# This is a SEPARATE role from the app-deploy role in iam_github.tf.
# The app-deploy role is scoped to ECR/ECS only.
# This role has AdministratorAccess so Terraform can manage all infra.
# Safety comes from the PR plan review step, not IAM scoping.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "github_terraform_ci_role" {
  name        = "${var.app_name_prefix}-${var.environment}-${var.infra_suffix}-terraform-ci-role"
  description = "Assumed by GitHub Actions (iac-arcadesbox) to run terraform plan/apply"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Scoped strictly to the iac-arcadesbox repo — all branches and PR refs
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/iac-arcadesbox:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_terraform_ci_admin" {
  role       = aws_iam_role.github_terraform_ci_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

output "github_terraform_ci_role_arn" {
  description = "ARN of the IAM role for the Terraform CI/CD pipeline — set this as the AWS_ROLE_ARN repo secret in iac-arcadesbox."
  value       = aws_iam_role.github_terraform_ci_role.arn
}
