resource "aws_lb" "app" {
  name               = "${var.app_name_prefix}-alb-${var.environment}-${var.infra_suffix}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    enabled = true
  }

  depends_on = [aws_s3_bucket_policy.alb_logs_policy]
}

resource "aws_lb_target_group" "app" {
  name        = "${var.app_name_prefix}-tg-${var.environment}-${var.infra_suffix}"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/api/health"
    protocol            = "HTTP"
    port                = "traffic-port" # Checks on port 5000
    healthy_threshold   = 2              # Number of successes to be considered healthy
    unhealthy_threshold = 3              # Number of failures to be considered unhealthy
    timeout             = 10             # Seconds to wait for a response
    interval            = 30             # Seconds between checks
    matcher             = "200"          # The HTTP status code to expect
  }
}

resource "aws_lb_listener" "app_http" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "app_https" {
  load_balancer_arn = aws_lb.app.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.api_cert_validation.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  depends_on = [time_sleep.wait_for_acm_replication]

}
