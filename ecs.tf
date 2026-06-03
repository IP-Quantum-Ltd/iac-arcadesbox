resource "aws_ecs_cluster" "main" {
  name = "${var.app_name_prefix}-ecs-cluster-${var.environment}-${var.infra_suffix}"
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

# --- Capacity Providers (Strategy) ---
resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name_prefix}-${var.environment}-${var.infra_suffix}"
  retention_in_days = 30 # Optional: Set a log retention period

  tags = {
    Project = var.app_name_prefix
    Env     = var.environment
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.app_name_prefix}-task-${var.environment}-${var.infra_suffix}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.environment == "development" ? "256" : var.ecs_task_cpu
  memory                   = var.environment == "development" ? "512" : var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  depends_on               = [aws_secretsmanager_secret.application_secrets]

  container_definitions = jsonencode([
    {
      name      = "${var.app_name_prefix}-ecs-backend-${var.environment}-server-${var.infra_suffix}"
      image     = "${aws_ecr_repository.chareli_server.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 5000
          hostPort      = 5000
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      # --- Environment block now only contains non-secret values ---
      environment = [
        { name = "AWS_REGION", value = var.aws_region },
        { name = "AWS_SECRET_NAME", value = aws_secretsmanager_secret.application_secrets.name },
        { name = "AWS_S3_BUCKET", value = aws_s3_bucket.games_bucket.id },
        { name = "CLIENT_URL", value = "https://${var.frontend_domain_name}" },
        { name = "SES_REGION", value = var.ses_region },
        { name = "R2_BUCKET_NAME", value = aws_s3_bucket.games_bucket.id },
        { name = "REDIS_HOST", value = var.enable_redis ? aws_elasticache_replication_group.redis[0].primary_endpoint_address : "" },
        { name = "REDIS_PORT", value = var.enable_redis ? tostring(aws_elasticache_replication_group.redis[0].port) : "" },
        { name = "REDIS_CACHE_ENABLED", value = "true" },
        { name = "REDIS_COMPRESSION_ENABLED", value = "true" },
        { name = "REDIS_CIRCUIT_BREAKER", value = "true" },
        { name = "LOG_FORMAT", value = "json" },
        { name = "APP_URL", value = "https://${var.api_domain_name}/api" },

        # AI agent base URL (Service Connect, internal). Server's
        # notifyProposalCreated POSTs to ${url}/webhook/proposal-created.
        { name = "AI_AGENT_INTERNAL_URL", value = "http://ai-agent:8000" }
      ]

      secrets = [
        # --- Database Credentials ---
        { name = "DB_HOST", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:DB_HOST::" },
        { name = "DB_PORT", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:DB_PORT::" },
        { name = "DB_USERNAME", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:DB_USERNAME::" },
        { name = "DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:DB_PASSWORD::" },
        { name = "DB_DATABASE", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:DB_DATABASE::" },

        # --- Application Configuration ---
        { name = "NODE_ENV", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:NODE_ENV::" },
        { name = "PORT", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:PORT::" },
        { name = "STORAGE_PROVIDER", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:STORAGE_PROVIDER::" },

        # --- JWT Configuration ---
        { name = "JWT_SECRET", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:JWT_SECRET::" },
        { name = "JWT_REFRESH_SECRET", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:JWT_REFRESH_SECRET::" },
        { name = "JWT_EXPIRATION", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:JWT_EXPIRATION::" },
        { name = "JWT_REFRESH_EXPIRATION", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:JWT_REFRESH_EXPIRATION::" },
        { name = "WORKER_JWT_SECRET", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:WORKER_JWT_SECRET::" },

        # --- Business Logic Configuration ---
        { name = "OTP_EXPIRY_MINUTES", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:OTP_EXPIRY_MINUTES::" },
        { name = "INVITATION_EXPIRY_DAYS", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:INVITATION_EXPIRY_DAYS::" },
        { name = "AWS_SIGNED_URL_EXPIRATION", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:AWS_SIGNED_URL_EXPIRATION::" },

        # --- Super Admin Credentials ---
        { name = "SUPERADMIN_EMAIL", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:SUPERADMIN_EMAIL::" },
        { name = "SUPERADMIN_PASSWORD", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:SUPERADMIN_PASSWORD::" },

        # --- Email Service Credentials (SES / Other) ---
        { name = "EMAIL_PROVIDER", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:EMAIL_PROVIDER::" },
        { name = "EMAIL_USER", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:EMAIL_USER::" },
        { name = "EMAIL_PASSWORD", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:EMAIL_PASSWORD::" },
        { name = "SES_FROM_EMAIL", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:SES_FROM_EMAIL::" },
        { name = "SENDGRID_FROM_EMAIL", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:SENDGRID_FROM_EMAIL::" },
        { name = "SENDGRID_API_KEY", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:SENDGRID_API_KEY::" },
        { name = "RESEND_API_KEY", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:RESEND_API_KEY::" },
        { name = "RESEND_FROM_EMAIL", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:RESEND_FROM_EMAIL::" },

        # --- Twilio Credentials ---
        { name = "USE_TWILIO", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:USE_TWILIO::" },
        { name = "TWILIO_ACCOUNT_SID", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:TWILIO_ACCOUNT_SID::" },
        { name = "TWILIO_AUTH_TOKEN", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:TWILIO_AUTH_TOKEN::" },
        { name = "TWILIO_SERVICE_SID", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:TWILIO_SERVICE_SID::" },

        # --- Cloudflare R2 Credentials ---
        { name = "CLOUDFLARE_ACCOUNT_ID", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:CLOUDFLARE_ACCOUNT_ID::" },
        { name = "R2_ACCESS_KEY_ID", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:R2_ACCESS_KEY_ID::" },
        { name = "R2_SECRET_ACCESS_KEY", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:R2_SECRET_ACCESS_KEY::" },
        { name = "R2_PUBLIC_URL", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:R2_PUBLIC_URL::" },
        { name = "R2_BUCKET", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:R2_BUCKET::" },

        # --- JSON CDN Settings ---
        { name = "JSON_CDN_ENABLED", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:JSON_CDN_ENABLED::" },
        { name = "JSON_CDN_BASE_URL", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:JSON_CDN_BASE_URL::" },
        { name = "JSON_CDN_REFRESH_INTERVAL", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:JSON_CDN_REFRESH_INTERVAL::" },
        { name = "ZIP_PROCESSING_MODE", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:ZIP_PROCESSING_MODE::" },
        { name = "LOAD_TEST_BYPASS_TOKEN", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:LOAD_TEST_BYPASS_TOKEN::" },

        # --- CDN Cache Management---
        { name = "CLOUDFLARE_API_TOKEN", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:CLOUDFLARE_API_TOKEN::" },
        { name = "CLOUDFLARE_CDN_ZONE_ID", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:CLOUDFLARE_CDN_ZONE_ID::" },
        { name = "CLOUDFLARE_KV_NAMESPACE_ID", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:CLOUDFLARE_KV_NAMESPACE_ID::" },
        { name = "CLOUDFLARE_WEBHOOK_SECRET", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:CLOUDFLARE_WEBHOOK_SECRET::" },

        # Shared secret used by notifyProposalCreated to authenticate against
        # the AI agent's /webhook/proposal-created endpoint. Same value must be
        # seeded as WEBHOOK_SECRET in ai-agent-secrets.
        { name = "AI_AGENT_WEBHOOK_SECRET", valueFrom = "${aws_secretsmanager_secret.application_secrets.arn}:AI_AGENT_WEBHOOK_SECRET::" },
      ]
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "${var.app_name_prefix}-service-${var.environment}-${var.infra_suffix}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count = var.environment == "production" ? 5 : (
    var.environment == "development" ? 1 : (var.staging_active ? 5 : 0)
  )
  #launch_type            = "FARGATE"
  enable_execute_command = local.enable_ecs_exec
  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition,
      load_balancer
    ]
  }

  network_configuration {
    subnets          = var.environment == "production" ? aws_subnet.private[*].id : aws_subnet.public[*].id
    assign_public_ip = var.environment == "production" ? false : true
    security_groups  = [aws_security_group.ecs_service.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "${var.app_name_prefix}-ecs-backend-${var.environment}-server-${var.infra_suffix}"
    container_port   = 5000
  }

  service_connect_configuration {
    enabled   = true
    namespace = aws_service_discovery_http_namespace.main.arn

    log_configuration {
      log_driver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "service-connect"
      }
    }
  }

  deployment_controller {
    type = "ECS"
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  capacity_provider_strategy {
    base              = var.environment == "development" ? 0 : 5
    weight            = 1
    capacity_provider = "FARGATE"
  }

  capacity_provider_strategy {
    base              = 0
    weight            = 4
    capacity_provider = "FARGATE_SPOT"
  }

  depends_on = [aws_lb_listener.app_https]
}
