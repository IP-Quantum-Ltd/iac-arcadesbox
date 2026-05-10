locals {
  # --- Standard ALB & ECS Widgets ---
  standard_widgets = [
    {
      type   = "metric"
      x      = 0
      y      = 0
      width  = 12
      height = 6
      properties = {
        metrics = [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.aws_region
        title   = "ALB Request Count"
        period  = 300
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 0
      width  = 12
      height = 6
      properties = {
        metrics = [
          ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.app.arn_suffix]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.aws_region
        title   = "ALB Latency (Average)"
        period  = 300
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 6
      width  = 12
      height = 6
      properties = {
        metrics = [
          ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", aws_lb.app.arn_suffix],
          ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.app.arn_suffix]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.aws_region
        title   = "ALB Errors (4xx/5xx)"
        period  = 300
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 6
      width  = 12
      height = 6
      properties = {
        metrics = [
          ["AWS/ECS", "CPUUtilization", "ServiceName", aws_ecs_service.app.name, "ClusterName", aws_ecs_cluster.main.name],
          ["AWS/ECS", "MemoryUtilization", "ServiceName", aws_ecs_service.app.name, "ClusterName", aws_ecs_cluster.main.name]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.aws_region
        title   = "ECS CPU & Memory"
        period  = 300
      }
    }
  ]

  # --- Redis Widgets (Conditional) ---
  # We use simple SEARCH expressions without complex math to ensure valid JSON structure.
  redis_widgets = var.enable_redis ? [
    {
      type   = "metric"
      x      = 0
      y      = 12
      width  = 12
      height = 6
      properties = {
        metrics = [
          [{ "expression" : "SEARCH('{AWS/ElastiCache,CacheClusterId} MetricName=\"EngineCPUUtilization\" ReplicationGroupId=\"${aws_elasticache_replication_group.redis[0].id}\"', 'Average', 300)", "label" : "Engine CPU", "id" : "m1" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.aws_region
        title   = "Redis Engine CPU"
        period  = 300
        yAxis   = { left = { min = 0, max = 100 } }
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 12
      width  = 12
      height = 6
      properties = {
        metrics = [
          [{ "expression" : "SEARCH('{AWS/ElastiCache,CacheClusterId} MetricName=\"DatabaseMemoryUsagePercentage\" ReplicationGroupId=\"${aws_elasticache_replication_group.redis[0].id}\"', 'Maximum', 300)", "label" : "Mem %", "id" : "m2" }]
        ]
        view    = "timeSeries"
        stacked = false
        region  = var.aws_region
        title   = "Redis Memory Usage %"
        period  = 300
        yAxis   = { left = { min = 0, max = 100 } }
      }
    }
  ] : []

  # --- Application Logs Widget ---
  logs_widgets = [
    {
      type   = "log"
      x      = 0
      y      = 18
      width  = 24
      height = 8
      properties = {
        title         = "Application Logs"
        region        = var.aws_region
        view          = "table"
        period        = 300
        query         = "SOURCE '${aws_cloudwatch_log_group.app.name}' | fields @timestamp, level, message, requestId | sort @timestamp desc | limit 200"
        logGroupNames = [aws_cloudwatch_log_group.app.name]
      }
    }
  ]
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.app_name_prefix}-dashboard-${var.environment}-${var.infra_suffix}"

  dashboard_body = jsonencode({
    widgets = concat(local.standard_widgets, local.redis_widgets, local.logs_widgets)
  })
}
