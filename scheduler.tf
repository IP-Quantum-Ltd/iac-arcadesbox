resource "aws_scheduler_schedule_group" "backup_schedule_group" {
  name = "${var.app_name_prefix}-backup-schedules-${var.environment}"
}

resource "aws_iam_role" "eventbridge_scheduler_ecs_role" {
  name = "${var.app_name_prefix}-eventbridge-scheduler-ecs-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "eventbridge_scheduler_ecs_policy" {
  name = "${var.app_name_prefix}-eventbridge-scheduler-ecs-policy-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = aws_ecs_task_definition.backup_tool.arn
        Condition = {
          StringEquals = { "ecs:cluster" = aws_ecs_cluster.main.arn }
        }
      },
      # Required to allow the scheduler to pass the task role
      {
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = [
          aws_iam_role.ecs_backup_task.arn,
          aws_iam_role.ecs_task_execution.arn
        ]
        Condition = {
          StringLike = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_scheduler_ecs_policy_attachment" {
  role       = aws_iam_role.eventbridge_scheduler_ecs_role.name
  policy_arn = aws_iam_policy.eventbridge_scheduler_ecs_policy.arn
}

resource "aws_scheduler_schedule" "run_daily_backup_task" {
  name       = "${var.app_name_prefix}-daily-storage-backup"
  group_name = aws_scheduler_schedule_group.backup_schedule_group.name

  flexible_time_window {
    mode = "OFF"
  }

  # Runs every day at 2:00 AM UTC
  schedule_expression = "cron(0 2 * * ? *)"

  target {
    arn      = aws_ecs_cluster.main.arn
    role_arn = aws_iam_role.eventbridge_scheduler_ecs_role.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.backup_tool.arn
      launch_type         = "FARGATE"

      network_configuration {
        subnets          = var.environment == "production" ? aws_subnet.private[*].id : aws_subnet.public[*].id
        assign_public_ip = var.environment == "production" ? false : true
        security_groups  = [aws_security_group.ecs_service.id] # Can likely re-use this SG
      }
    }
  }
}
