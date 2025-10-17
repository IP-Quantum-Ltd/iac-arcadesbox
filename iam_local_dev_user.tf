# iam_local_dev_user.tf

# -----------------------------------------------------------------------------
# IAM User for Local Development
# -----------------------------------------------------------------------------
resource "aws_iam_user" "local_dev_user" {
  count = var.create_local_dev_user ? 1 : 0
  name  = "${var.local_dev_user_name}-${var.environment}-${var.infra_suffix}"
}

# -----------------------------------------------------------------------------
# IAM Policy for the Local Development User
# Grants necessary permissions for local dev against dev AWS resources.
# This should be LEAST PRIVILEGE.
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "local_dev_user_policy_doc" {
  statement {
    sid    = "SecretsManagerDevAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [ # ARNs of dev secrets
      aws_secretsmanager_secret.application_secrets.arn
    ]
  }


  statement {
    sid    = "SESDevAccess"
    effect = "Allow"
    actions = [
      "ses:SendEmail",
      "ses:SendRawEmail",
      "ses:VerifyDomainIdentity", # If you ever test domain verification scripts locally
      "ses:VerifyEmailIdentity",  # If you ever test email verification scripts locally
      "ses:ListIdentities"        # Useful for dev
    ]
    # Scope to dev identities if possible, or "*" for dev is often acceptable
    resources = ["*"]
  }

  # Add ECR pull access if local dev ever needs to pull images (less common for app dev, more for ops)
  # statement {
  #   sid    = "ECRDevPull"
  #   effect = "Allow"
  #   actions = [
  #     "ecr:GetAuthorizationToken",
  #     "ecr:BatchGetImage",
  #     "ecr:GetDownloadUrlForLayer"
  #   ],
  #   resources = ["*"] # Scope to specific ECR repo if needed
  # }

  # Add more permissions as needed for local development (e.g., App Runner describe, logs)
  # Always apply LEAST PRIVILEGE.
}

resource "aws_iam_policy" "local_dev_user_policy" {
  count       = var.create_local_dev_user ? 1 : 0
  name        = "${var.app_name_prefix}-local-dev-user-policy-${var.environment}"
  description = "Policy for Chareli local development IAM user."
  policy      = data.aws_iam_policy_document.local_dev_user_policy_doc.json
}

resource "aws_iam_user_policy_attachment" "local_dev_user_policy_attachment" {
  count      = var.create_local_dev_user ? 1 : 0
  user       = aws_iam_user.local_dev_user[0].name
  policy_arn = aws_iam_policy.local_dev_user_policy[0].arn
}

# -----------------------------------------------------------------------------
# Access Key for the Local Development User
# The secret_key will be written to the state file and output on creation.
# Secure this output carefully.
# -----------------------------------------------------------------------------
resource "aws_iam_access_key" "local_dev_user_key" {
  count = var.create_local_dev_user ? 1 : 0
  user  = aws_iam_user.local_dev_user[0].name
  # Optional: PGP key for encrypting the secret access key in the output
  # pgp_key = "keybase:yourkeybaseusername"
}

# -----------------------------------------------------------------------------
# Outputs for Local Dev User Credentials (Handle with Extreme Care)
# These will only be shown when the access key is first created or rotated by Terraform.
# -----------------------------------------------------------------------------
output "local_dev_user_access_key_id" {
  description = "Access Key ID for the local development IAM user. Store securely."
  value       = length(aws_iam_access_key.local_dev_user_key) > 0 ? aws_iam_access_key.local_dev_user_key[0].id : ""
  depends_on  = [aws_iam_access_key.local_dev_user_key]
}

output "local_dev_user_secret_access_key" {
  description = "Secret Access Key for the local development IAM user. STORE THIS SECURELY AND IMMEDIATELY. It will not be shown again."
  value       = length(aws_iam_access_key.local_dev_user_key) > 0 ? aws_iam_access_key.local_dev_user_key[0].secret : ""
  sensitive   = true # Marks this output as sensitive in Terraform logs
  depends_on  = [aws_iam_access_key.local_dev_user_key]
}
