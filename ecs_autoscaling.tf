# 1. Register the ECS service as a scalable target
resource "aws_appautoscaling_target" "ecs_service" {
  # Enable for Prod AND Staging
  count = var.environment != "development" ? 1 : 0
  # The service to scale
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount" # The attribute to scale (number of tasks)
  service_namespace  = "ecs"                      # The AWS service namespace

  # Staging (Active): Min 5
  min_capacity = var.environment == "production" ? var.min_capacity : (var.staging_active ? var.min_capacity : 0)

  # Same logic for Max capacity (Optional, but good practice)
  max_capacity = var.environment == "production" ? var.max_capacity : (var.staging_active ? var.max_capacity : 0)
}

# 2. Create the "Scale Up" policy (add tasks when busy)
resource "aws_appautoscaling_policy" "scale_up_cpu" {
  # Enable for Prod AND Staging
  count              = var.environment != "development" ? 1 : 0
  name               = "${var.app_name_prefix}-scale-up-cpu-${var.environment}-${var.infra_suffix}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[0].service_namespace

  target_tracking_scaling_policy_configuration {
    # The metric to track
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    # The target value for the metric
    target_value = 60.0 # Scale earlier at 60% to prevent saturation

    # How quickly to scale up (add tasks)
    scale_in_cooldown  = 180 # Wait 3 minutes after scale-in (less aggressive)
    scale_out_cooldown = 10  # Wait 10 seconds after scale-out (very aggressive)
  }
}

# 3. Create the "Scale Down" policy (remove tasks when idle)
# Note: You only need one target tracking policy for both scale-up and scale-down.
# CloudWatch automatically creates the necessary alarms to handle both directions.
# The `scale_up_cpu` policy above is sufficient for both scaling up and down based on the 75% target.


resource "aws_appautoscaling_policy" "scale_up_memory" {
  # Enable for Prod AND Staging
  count              = var.environment != "development" ? 1 : 0
  name               = "${var.app_name_prefix}-scale-up-memory-${var.environment}-${var.infra_suffix}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value = 60.0 # Scale earlier at 60% to prevent saturation

    scale_in_cooldown  = 180
    scale_out_cooldown = 10
  }
}

resource "aws_appautoscaling_policy" "scale_by_rps" {
  # Enable for Prod AND Staging
  count              = var.environment != "development" ? 1 : 0
  name               = "${var.app_name_prefix}-scale-by-rps-${var.environment}-${var.infra_suffix}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service[0].service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.app.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }

    target_value       = 1000.0 # Lower threshold for scaling
    scale_in_cooldown  = 180
    scale_out_cooldown = 10
  }
}
