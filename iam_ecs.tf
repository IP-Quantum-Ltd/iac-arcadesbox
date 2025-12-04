# iam_ecs.tf

# -----------------------------------------------------------------------------
# IAM for ECS Task Execution Role (The "Stage Crew")
# This role prepares the container (pulls image, fetches secrets).
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.app_name_prefix}-ecs-task-execution-${var.environment}-${var.infra_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role_policy.json
}

data "aws_iam_policy_document" "ecs_task_execution_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# --- This is the NEW POLICY just for the EXECUTION ROLE ---
data "aws_iam_policy_document" "ecs_task_execution_secrets_policy_doc" {
  statement {
    sid     = "SecretsManagerAccessForECS"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    # It needs access to BOTH secrets that are injected via the 'secrets' block
    resources = [
      aws_secretsmanager_secret.application_secrets.arn,
      aws_secretsmanager_secret.backup_tool_secrets.arn
    ]
  }
}

# Allow ECS Exec / SSM Session Manager access for ECS Exec
resource "aws_iam_role_policy_attachment" "ecs_task_execution_ssm" {
  count      = local.enable_ecs_exec ? 1 : 0
  role       = aws_iam_role.ecs_task.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


resource "aws_iam_policy" "ecs_task_execution_secrets_policy" {
  name   = "${var.app_name_prefix}-ecs-execution-secrets-policy-${var.environment}-${var.infra_suffix}"
  policy = data.aws_iam_policy_document.ecs_task_execution_secrets_policy_doc.json
}

# Attach the standard AWS-managed policy for ECR and CloudWatch Logs
resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Attach our NEW custom policy for fetching secrets
resource "aws_iam_role_policy_attachment" "ecs_task_execution_custom_secrets_attachment" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = aws_iam_policy.ecs_task_execution_secrets_policy.arn
}


# -----------------------------------------------------------------------------
# IAM for ECS Task Role (The "Actor")
# This is the role the application uses when it's running.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_task" {
  name               = "${var.app_name_prefix}-ecs-task-role-${var.environment}-${var.infra_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role_policy.json
}

# --- This policy is now ONLY for the TASK ROLE ---
data "aws_iam_policy_document" "ecs_task_policy_doc" {
  # This statement is no longer needed here, as the app doesn't fetch secrets directly.
  # We can leave it for now to avoid complexity, but could be removed.
  statement {
    sid     = "SecretsManagerAppConfigAccess"
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.application_secrets.arn,
    ]
  }


  statement {
    sid       = "SESAccess"
    effect    = "Allow"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecs_task_policy" {
  name   = "${var.app_name_prefix}-ecs-task-policy-${var.environment}-${var.infra_suffix}"
  policy = data.aws_iam_policy_document.ecs_task_policy_doc.json
}

# This attachment now only applies to the TASK ROLE
resource "aws_iam_role_policy_attachment" "ecs_task_policy_attachment" {
  role       = aws_iam_role.ecs_task.name # <<< Points to the task role
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}
