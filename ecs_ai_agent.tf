resource "aws_cloudwatch_log_group" "ai_agent" {
  name              = "/ecs/${var.app_name_prefix}-ai-agent-${var.environment}-${var.infra_suffix}"
  retention_in_days = 30

  tags = {
    Project = var.app_name_prefix
    Env     = var.environment
  }
}

resource "aws_ecs_task_definition" "ai_agent" {
  family                   = "${var.app_name_prefix}-ai-agent-task-${var.environment}-${var.infra_suffix}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.environment == "development" ? "512" : var.ai_agent_cpu
  memory                   = var.environment == "development" ? "2048" : var.ai_agent_memory
  execution_role_arn       = aws_iam_role.ai_agent_task_execution.arn
  task_role_arn            = aws_iam_role.ai_agent_task.arn
  depends_on               = [aws_secretsmanager_secret.ai_agent_secrets]

  container_definitions = jsonencode([
    {
      name      = "${var.app_name_prefix}-ai-agent-${var.environment}-${var.infra_suffix}"
      image     = "${aws_ecr_repository.ai_agent.repository_url}:${var.ai_agent_image_tag}"
      essential = true

      portMappings = [
        {
          name          = "ai-agent-http"
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ai_agent.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "AWS_SECRET_NAME", value = aws_secretsmanager_secret.ai_agent_secrets.name },
        { name = "ENVIRONMENT", value = var.environment },

        # Stage 0 artifact storage. Reuses the existing R2 games bucket under a
        # dedicated prefix so artifacts and game CDN assets stay isolated.
        { name = "STORAGE_PROVIDER", value = "r2" },
        { name = "AWS_S3_BUCKET", value = aws_s3_bucket.games_bucket.id },
        { name = "R2_BUCKET_NAME", value = aws_s3_bucket.games_bucket.id },
        { name = "AI_AGENT_S3_PREFIX", value = "ai-agent/stage0" },
        { name = "GAME_SWEEP_ENABLED", value = "true" },
        { name = "GAME_SWEEP_SCHEDULE", value = "weekly" },
        { name = "GAME_SWEEP_DAY", value = "tue" },
        { name = "GAME_SWEEP_HOUR", value = "17" },
        { name = "GAME_SWEEP_MINUTE", value = "0" }
      ]

      secrets = [
        { name = "ARCADE_API_BASE_URL", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:ARCADE_API_BASE_URL::" },
        { name = "ARCADE_API_TOKEN", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:ARCADE_API_TOKEN::" },

        { name = "AI_PROVIDER", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:AI_PROVIDER::" },
        { name = "OPENAI_API_KEY", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:OPENAI_API_KEY::" },
        { name = "ANTHROPIC_API_KEY", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:ANTHROPIC_API_KEY::" },
        { name = "PRIMARY_LLM_MODEL", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:PRIMARY_LLM_MODEL::" },
        { name = "SECONDARY_LLM_MODEL", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:SECONDARY_LLM_MODEL::" },
        { name = "EMBEDDING_MODEL", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:EMBEDDING_MODEL::" },
        { name = "OPENAI_WEB_SEARCH_MODEL", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:OPENAI_WEB_SEARCH_MODEL::" },

        { name = "DATABASE_URL", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:DATABASE_URL::" },
        { name = "DB_HOST", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:DB_HOST::" },
        { name = "DB_PORT", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:DB_PORT::" },
        { name = "DB_USERNAME", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:DB_USERNAME::" },
        { name = "DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:DB_PASSWORD::" },
        { name = "DB_DATABASE", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:DB_DATABASE::" },

        { name = "MONGODB_URL", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:MONGODB_URL::" },
        { name = "MONGODB_DB_NAME", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:MONGODB_DB_NAME::" },
        { name = "MONGODB_RAG_COLLECTION", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:MONGODB_RAG_COLLECTION::" },
        { name = "MONGODB_VECTOR_INDEX", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:MONGODB_VECTOR_INDEX::" },
        { name = "MONGODB_EVALUATION_COLLECTION", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:MONGODB_EVALUATION_COLLECTION::" },

        { name = "CLIENT_URL", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:CLIENT_URL::" },
        { name = "BROWSER_VIEWPORT_WIDTH", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:BROWSER_VIEWPORT_WIDTH::" },
        { name = "BROWSER_VIEWPORT_HEIGHT", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:BROWSER_VIEWPORT_HEIGHT::" },
        { name = "EXTERNAL_PAGE_TIMEOUT_MS", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:EXTERNAL_PAGE_TIMEOUT_MS::" },
        { name = "INTERNAL_PAGE_TIMEOUT_MS", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:INTERNAL_PAGE_TIMEOUT_MS::" },

        { name = "WEBHOOK_SECRET", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:WEBHOOK_SECRET::" },

        # R2 credentials. Same values as the Server (application_secrets) — the
        # ai-agent uses them under the AI_AGENT_S3_PREFIX prefix on games_bucket.
        { name = "CLOUDFLARE_ACCOUNT_ID", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:CLOUDFLARE_ACCOUNT_ID::" },
        { name = "R2_ACCESS_KEY_ID", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:R2_ACCESS_KEY_ID::" },
        { name = "R2_SECRET_ACCESS_KEY", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:R2_SECRET_ACCESS_KEY::" },
        { name = "R2_PUBLIC_URL", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:R2_PUBLIC_URL::" },

        { name = "CRON_INTERVAL_MINUTES", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:CRON_INTERVAL_MINUTES::" },
        { name = "MAX_PLAN_REVISIONS", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:MAX_PLAN_REVISIONS::" },
        { name = "MAX_DRAFT_REVISIONS", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:MAX_DRAFT_REVISIONS::" },
        { name = "JOB_RETENTION_HOURS", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:JOB_RETENTION_HOURS::" },
        { name = "STAGE0_REQUIRED_CANDIDATES", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:STAGE0_REQUIRED_CANDIDATES::" },
        { name = "STAGE0_MAX_SEARCH_RESULTS", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:STAGE0_MAX_SEARCH_RESULTS::" },
        { name = "STAGE0_CANDIDATE_CAPTURE_TIMEOUT_SECONDS", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:STAGE0_CANDIDATE_CAPTURE_TIMEOUT_SECONDS::" },

        { name = "LANGCHAIN_TRACING_V2", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:LANGCHAIN_TRACING_V2::" },
        { name = "LANGCHAIN_API_KEY", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:LANGCHAIN_API_KEY::" },
        { name = "LANGCHAIN_PROJECT", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:LANGCHAIN_PROJECT::" },
        { name = "LANGCHAIN_ENDPOINT", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:LANGCHAIN_ENDPOINT::" },
        { name = "LANGSMITH_TRACING", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:LANGSMITH_TRACING::" },
        { name = "LANGSMITH_API_KEY", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:LANGSMITH_API_KEY::" },
        { name = "LANGSMITH_PROJECT", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:LANGSMITH_PROJECT::" },
        { name = "LANGSMITH_ENDPOINT", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:LANGSMITH_ENDPOINT::" },
        { name = "AWS_ACCESS_KEY_ID", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:AWS_ACCESS_KEY_ID::" },
        { name = "AWS_SECRET_ACCESS_KEY", valueFrom = "${aws_secretsmanager_secret.ai_agent_secrets.arn}:AWS_SECRET_ACCESS_KEY::" },
      ]
    }
  ])
}

resource "aws_ecs_service" "ai_agent" {
  name            = "${var.app_name_prefix}-ai-agent-service-${var.environment}-${var.infra_suffix}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ai_agent.arn

  # Single task by design — the in-memory job queue does not support
  # multiple workers. Bumping desired_count requires the Redis-backed
  # queue tracked in chareli/ai-agent/docs/progress-tracker.md (Phase VI 6.1).
  desired_count = var.environment == "production" ? (var.ai_agent_active ? 1 : 0) : (
    var.environment == "development" ? 0 : (var.ai_agent_active ? 1 : 0)
  )

  enable_execute_command = local.enable_ecs_exec

  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition
    ]
  }

  network_configuration {
    subnets          = var.environment == "production" ? aws_subnet.private[*].id : aws_subnet.public[*].id
    assign_public_ip = var.environment == "production" ? false : true
    security_groups  = [aws_security_group.ai_agent_service.id]
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    service {
      port_name      = "ai-agent-http"
      discovery_name = "ai-agent"

      client_alias {
        port     = 8000
        dns_name = "ai-agent"
      }
    }

    log_configuration {
      log_driver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ai_agent.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "service-connect"
      }
    }
  }

  deployment_controller {
    type = "ECS"
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  capacity_provider_strategy {
    base              = 1
    weight            = 1
    capacity_provider = "FARGATE"
  }
}
