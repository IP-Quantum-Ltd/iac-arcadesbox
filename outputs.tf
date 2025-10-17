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

# output "worker_script_name" {
#   description = "The name of the deployed Cloudflare Worker script."
#   value       = cloudflare_workers_script.game_cdn_worker[0].script_name
# }


# output "worker_url" {
#   description = "The full, public *.workers.dev URL for the deployed worker."
#   value       = "https://${cloudflare_workers_script.game_cdn_worker[0].script_name}.${var.cloudflare_workers_subdomain}"
# }


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
