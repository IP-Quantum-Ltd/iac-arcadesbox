# Security group for the AI agent ECS service.
# Ingress: only the main backend's ECS SG can reach port 8000. No public path.
# Egress: all (NAT GW in prod, IGW in non-prod) — needed for OpenAI, Anthropic,
# MongoDB Atlas, LangSmith, and the main backend's public API.
resource "aws_security_group" "ai_agent_service" {
  name        = "${var.app_name_prefix}-ai-agent-sg-${var.environment}-${var.infra_suffix}"
  description = "Controls access to the AI agent ECS tasks"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "ai_agent_from_backend" {
  security_group_id            = aws_security_group.ai_agent_service.id
  description                  = "Allow inbound 8000 from main backend ECS service"
  from_port                    = 8000
  to_port                      = 8000
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.ecs_service.id
}

resource "aws_vpc_security_group_egress_rule" "ai_agent_egress_all" {
  security_group_id = aws_security_group.ai_agent_service.id
  description       = "All egress (LLM providers, Atlas, LangSmith)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
