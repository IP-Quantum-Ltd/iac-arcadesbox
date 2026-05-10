# Cloud Map HTTP namespace used by ECS Service Connect.
# Internal-only DNS for service-to-service traffic inside the cluster — no ALB,
# no Route 53. The main backend resolves the AI agent at http://ai-agent:8000
# via the Service Connect proxy (Envoy) injected by ECS.
resource "aws_service_discovery_http_namespace" "main" {
  name        = "${var.app_name_prefix}-${var.environment}.local"
  description = "Service Connect namespace for ${var.app_name_prefix} (${var.environment}-${var.infra_suffix})"
}

output "service_connect_namespace_arn" {
  description = "ARN of the Service Connect HTTP namespace."
  value       = aws_service_discovery_http_namespace.main.arn
}
