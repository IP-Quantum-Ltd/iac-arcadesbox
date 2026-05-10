output "ses_sending_domain_identity_arn" {
  description = "ARN of the SES domain identity for the app"
  value       = aws_ses_domain_identity.chareli_sending_domain.arn
}

output "ses_from_email_identity_arn" {
  description = "ARN of the SES 'From' email identity for the app"
  value       = aws_ses_email_identity.chareli_from_email.arn
}

output "ses_domain_verification_token" {
  description = "SES domain verification TXT record value (if needed for manual DNS)"
  value       = aws_ses_domain_identity.chareli_sending_domain.verification_token
  sensitive   = true # Good practice for tokens
}

output "ses_dkim_cname_records" {
  description = "DKIM CNAME records that need to be created in DNS (name: value)"
  value = {
    for token in aws_ses_domain_dkim.chareli_sending_domain_dkim.dkim_tokens :
    "${token}._domainkey.${var.ses_sending_domain}" => "${token}.dkim.amazonses.com"
  }
}


# --- Cloudflare Worker Outputs ---

output "worker_script_name" {
  description = "The name of the deployed Cloudflare Worker script."
  value       = cloudflare_workers_script.game_zip_processor_worker.script_name
}

# --- Cloudflare KV Outputs ---

output "kv_namespace_id" {
  description = "The ID of the Workers KV namespace for game status tracking. Use in wrangler.toml."
  value       = cloudflare_workers_kv_namespace.game_status.id
}

output "kv_namespace_title" {
  description = "The title of the Workers KV namespace."
  value       = cloudflare_workers_kv_namespace.game_status.title
}

# --- Cloudflare Queue Outputs ---

output "game_zip_queue_name" {
  description = "The name of the main game ZIP processing queue."
  value       = cloudflare_queue.game_zip_queue.queue_name
}

output "game_zip_queue_id" {
  description = "The ID of the main game ZIP processing queue."
  value       = cloudflare_queue.game_zip_queue.id
}

output "game_zip_dlq_name" {
  description = "The name of the dead letter queue for failed game processing."
  value       = cloudflare_queue.game_zip_dlq.queue_name
}

output "game_zip_dlq_id" {
  description = "The ID of the dead letter queue."
  value       = cloudflare_queue.game_zip_dlq.id
}


# --- AI Agent Outputs ---

output "ai_agent_log_group_name" {
  description = "CloudWatch log group for the AI agent ECS service."
  value       = aws_cloudwatch_log_group.ai_agent.name
}

output "ai_agent_service_name" {
  description = "ECS service name for the AI agent."
  value       = aws_ecs_service.ai_agent.name
}

output "ai_agent_task_family" {
  description = "ECS task definition family for the AI agent."
  value       = aws_ecs_task_definition.ai_agent.family
}

output "ai_agent_security_group_id" {
  description = "Security group attached to the AI agent ECS tasks."
  value       = aws_security_group.ai_agent_service.id
}

# --- ElastiCache Redis Outputs ---

output "redis_primary_endpoint" {
  description = "The primary endpoint address for the ElastiCache Redis cluster. Use this for read/write operations."
  # This conditional logic prevents an error if Redis is disabled for an environment.
  value = var.enable_redis ? aws_elasticache_replication_group.redis[0].primary_endpoint_address : "Redis not enabled"
}

output "redis_port" {
  description = "The port for the ElastiCache Redis cluster."
  value       = var.enable_redis ? aws_elasticache_replication_group.redis[0].port : "Redis not enabled"
}

output "redis_reader_endpoint" {
  description = "The reader endpoint address for the ElastiCache Redis cluster. Use this for read-only operations."
  # This endpoint only exists if you have more than one node (replicas).
  value = var.enable_redis ? aws_elasticache_replication_group.redis[0].reader_endpoint_address : "Redis not enabled"
}
