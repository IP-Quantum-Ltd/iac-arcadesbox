# 1. Register the ECS service as a scalable target
resource "aws_appautoscaling_target" "ecs_service" {
  # The service to scale
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount" # The attribute to scale (number of tasks)
  service_namespace  = "ecs"                      # The AWS service namespace

  # Define the boundaries for scaling
  min_capacity = 1  # Minimum number of tasks to run
  max_capacity = 20 # Maximum number of tasks to scale up to
}

# 2. Create the "Scale Up" policy (add tasks when busy)
resource "aws_appautoscaling_policy" "scale_up_cpu" {
  name               = "${var.app_name_prefix}-scale-up-cpu-${var.environment}-${var.infra_suffix}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service.service_namespace

  target_tracking_scaling_policy_configuration {
    # The metric to track
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    # The target value for the metric
    target_value = 75.0 # Scale up if average CPU utilization goes above 75%

    # How quickly to scale up (add tasks)
    scale_in_cooldown  = 300 # Wait 5 minutes after a scale-in before another scale-in can happen
    scale_out_cooldown = 60  # Wait 1 minute after a scale-out before another scale-out can happen
  }
}

# 3. Create the "Scale Down" policy (remove tasks when idle)
# Note: You only need one target tracking policy for both scale-up and scale-down.
# CloudWatch automatically creates the necessary alarms to handle both directions.
# The `scale_up_cpu` policy above is sufficient for both scaling up and down based on the 75% target.


resource "aws_appautoscaling_policy" "scale_up_memory" {
  name               = "${var.app_name_prefix}-scale-up-memory-${var.environment}-${var.infra_suffix}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value = 75.0 # Scale up if average memory utilization goes above 75%

    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

resource "aws_appautoscaling_policy" "scale_by_rps" {
  name               = "${var.app_name_prefix}-scale-by-rps-${var.environment}-${var.infra_suffix}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.app.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }

    target_value       = 150.0 # target 150 requests per second per task
    scale_in_cooldown  = 300
    scale_out_cooldown = 30
  }
}
