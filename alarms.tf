resource "aws_sns_topic" "alerts" {
  name = "${var.app_name_prefix}-alerts-${var.environment}-${var.infra_suffix}"
}

# --- ALB Alarms ---

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.app_name_prefix}-alb-high-5xx-${var.environment}-${var.infra_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors ALB 5xx errors"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_latency" {
  alarm_name          = "${var.app_name_prefix}-alb-high-latency-${var.environment}-${var.infra_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "2"
  alarm_description   = "This metric monitors ALB target response time"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.app.arn_suffix
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# --- ECS Alarms ---

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${var.app_name_prefix}-ecs-high-cpu-${var.environment}-${var.infra_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors ECS CPU utilization"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory" {
  alarm_name          = "${var.app_name_prefix}-ecs-high-memory-${var.environment}-${var.infra_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "This metric monitors ECS Memory utilization"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# --- Redis Alarms ---

locals {
  # Calculate how many nodes we expect based on the environment logic in elasticache.tf
  # This avoids "value depends on apply" errors.
  redis_node_count = var.enable_redis ? (var.environment == "production" ? 2 : 1) : 0

  # Generate a map of expected Node IDs: e.g. "001" => "cluster-id-001"
  redis_nodes = {
    for i in range(local.redis_node_count) :
    format("%03d", i + 1) => "${aws_elasticache_replication_group.redis[0].id}-${format("%03d", i + 1)}"
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  for_each = local.redis_nodes

  alarm_name          = "${var.app_name_prefix}-redis-cpu-${each.key}-${var.environment}-${var.infra_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "EngineCPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "60"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "Redis Engine CPU high on node ${each.key}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    CacheClusterId = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  for_each = local.redis_nodes

  alarm_name          = "${var.app_name_prefix}-redis-mem-${each.key}-${var.environment}-${var.infra_suffix}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = "60"
  statistic           = "Average"
  threshold           = "90"
  alarm_description   = "Redis Memory high on node ${each.key}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    CacheClusterId = each.value
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}
