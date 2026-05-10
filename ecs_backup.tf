# =================================================================
# IAM Role and Policy for the Backup Task
# =================================================================

resource "aws_iam_role" "ecs_backup_task" {
  name               = "${var.app_name_prefix}-ecs-backup-task-role-${var.environment}-${var.infra_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role_policy.json
}

data "aws_iam_policy_document" "ecs_backup_task_policy_doc" {
  # Permission to read secrets from Secrets Manager
  statement {
    sid    = "SecretsManagerAccess"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue"
    ]
    resources = [aws_secretsmanager_secret.backup_tool_secrets.arn]
  }

  # Permissions for the S3 backup bucket
  statement {
    sid    = "S3BackupBucketAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]
    resources = [
      aws_s3_bucket.aws_backup_bucket.arn,
      "${aws_s3_bucket.aws_backup_bucket.arn}/*" # Important to include objects inside the bucket
    ]
  }

  # Permissions for DynamoDB Lock

  statement {
    sid    = "DynamoDBLockingAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem"
    ]
    # Restrict permissions to only the lock table we created
    resources = [aws_dynamodb_table.job_lock_table.arn]
  }
}

resource "aws_iam_policy" "ecs_backup_task_policy" {
  name   = "${var.app_name_prefix}-ecs-backup-task-policy-${var.environment}-${var.infra_suffix}"
  policy = data.aws_iam_policy_document.ecs_backup_task_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "ecs_backup_task_policy_attachment" {
  role       = aws_iam_role.ecs_backup_task.name
  policy_arn = aws_iam_policy.ecs_backup_task_policy.arn
}

# =================================================================
# ECS Task Definition for the Backup Job
# =================================================================

resource "aws_cloudwatch_log_group" "backup_tool" {
  name              = "/ecs/${var.app_name_prefix}-backup-tool-${var.environment}-${var.infra_suffix}"
  retention_in_days = 30

  tags = {
    Project     = var.app_name_prefix
    Environment = var.environment
    Component   = "BackupTool"
  }
}

resource "aws_ecs_task_definition" "backup_tool" {
  family                   = "${var.app_name_prefix}-backup-tool-${var.environment}-${var.infra_suffix}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn # Re-use the standard execution role
  task_role_arn            = aws_iam_role.ecs_backup_task.arn    # Use our new dedicated task role

  container_definitions = jsonencode([
    {
      name      = "backup-tool"
      image     = "${aws_ecr_repository.backup_tool.repository_url}:latest"
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backup_tool.name # Use dedicated log group
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "backup-tool"
        }
      }
      # Secrets are injected as environment variables
      secrets = [
        { name = "R2_SOURCE_ACCESS_KEY", valueFrom = "${aws_secretsmanager_secret.backup_tool_secrets.arn}:R2_SOURCE_ACCESS_KEY::" },
        { name = "R2_SOURCE_SECRET_KEY", valueFrom = "${aws_secretsmanager_secret.backup_tool_secrets.arn}:R2_SOURCE_SECRET_KEY::" },
        { name = "R2_SOURCE_ENDPOINT", valueFrom = "${aws_secretsmanager_secret.backup_tool_secrets.arn}:R2_SOURCE_ENDPOINT::" },
        { name = "R2_DEST_ACCESS_KEY", valueFrom = "${aws_secretsmanager_secret.backup_tool_secrets.arn}:R2_DEST_ACCESS_KEY::" },
        { name = "R2_DEST_SECRET_KEY", valueFrom = "${aws_secretsmanager_secret.backup_tool_secrets.arn}:R2_DEST_SECRET_KEY::" },
        { name = "R2_DEST_ENDPOINT", valueFrom = "${aws_secretsmanager_secret.backup_tool_secrets.arn}:R2_DEST_ENDPOINT::" }
      ]
      # Non-secret environment variables
      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "AWS_S3_BUCKET", value = aws_s3_bucket.aws_backup_bucket.id },
        { name = "R2_SOURCE_BUCKET", value = aws_s3_bucket.games_bucket.id },
        { name = "R2_DEST_BUCKET", value = aws_s3_bucket.r2_backup_bucket.id },
        { name = "LOCK_TABLE_NAME", value = aws_dynamodb_table.job_lock_table.name }
      ]
    }
  ])
}
