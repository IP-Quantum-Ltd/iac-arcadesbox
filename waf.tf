resource "aws_wafv2_web_acl" "alb_protection" {
  # ONLY CREATE IN PRODUCTION
  count = var.environment == "production" ? 1 : 0

  name        = "${var.app_name_prefix}-alb-waf-${var.environment}"
  description = "Protect ALB and ensure traffic comes from Cloudflare"
  scope       = "REGIONAL"

  default_action {
    block {} # Block everything that doesn't match the rule
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "ALBWAF-${var.environment}"
    sampled_requests_enabled   = true
  }

  # Rule: Allow only if Secret Header exists
  rule {
    name     = "AllowCloudflareSecret"
    priority = 1

    action {
      allow {}
    }

    statement {
      byte_match_statement {
        search_string = var.cf_verify_secret
        field_to_match {
          single_header {
            name = "x-cf-verify" # The header name (must be lowercase in config)
          }
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
        positional_constraint = "EXACTLY"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AllowCloudflare"
      sampled_requests_enabled   = true
    }
  }
}

resource "aws_wafv2_web_acl_association" "alb_assoc" {
  # ONLY ASSOCIATE IN PRODUCTION
  count = var.environment == "production" ? 1 : 0

  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.alb_protection[0].arn
}
