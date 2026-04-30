variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
}

variable "ses_region" {
  description = "AWS region for the SES provider"
  type        = string
}
variable "app_name_prefix" {
  description = "A name prefix for resources"
  type        = string
  default     = "arcadesbox"
}

variable "app_port" {
  description = "The port your application listens on inside the container"
  type        = number
  default     = 5000
}
variable "environment" {
  description = "Deployment environment"
  type        = string
}
variable "image_tag" {
  description = "The Docker image tag to deploy (e.g., 'latest', 'v1.2.3', or a git SHA)."
  type        = string
  default     = "latest"
}

variable "frontend_domain_name" {
  description = "Custom domain for the React app (e.g., api.dev.chareli.reallygreattech.com)"
  type        = string
}

variable "api_domain_name" {
  description = "Custom domain for the api (e.g., dev.chareli.yourdomain.com)"
  type        = string
}

variable "games_cdn_domain_name" {
  description = "Custom domain for the games CDN (e.g., games-cdn.dev.chareli.yourdomain.com)"
  type        = string
}
variable "ses_sending_domain" {
  description = "The domain to verify for sending SES emails in dev (e.g., dev.chareli.yourdomain.com)"
  type        = string
}
variable "ses_from_email_address" {
  description = "The primary 'From' email address to verify for SES in dev (e.g., no-reply@dev.chareli.yourdomain.com)"
  type        = string
}
variable "local_dev_user_name" {
  description = "Name for the IAM user for local development"
  type        = string
  default     = "chareli-local-dev-user"
}
variable "create_local_dev_user" {
  description = "Set to true to create the IAM user for local development."
  type        = bool
  default     = false
}

variable "github_org" {
  description = "GitHub organization or user"
  type        = string
}
variable "github_repo" {
  description = "GitHub repository"
  type        = string
}

variable "r2_account_id" {
  description = "Account ID for the cloudflare account"
  type        = string
}

variable "r2_access_key_id" {
  description = "Access keys for the cloudflare account"
  type        = string
}

variable "r2_secret_access_key" {
  description = "Secret key for the cloudflare account"
  type        = string
  sensitive   = true
}

variable "github_branch" {
  description = "GitHub branch to allow access"
  type        = string
  default     = "main"
}

variable "root_domain_name" {
  description = "Root domain for the app"
  type        = string
}

variable "cloudflare_pages_cname_target" {
  description = "CNAME for the cloudflare pages"
  type        = string
}

variable "r2_public_cname_target" {
  description = "CNAME for the r2 bucket"
  type        = string
}

variable "infra_suffix" {
  description = "A suffix to append to resource names for uniqueness (e.g., 'v2')."
  type        = string
}

variable "worker_jwt_secret" {
  description = "A suffix to append to resource names for uniqueness (e.g., 'v2')."
  type        = string
}


variable "cloudflare_workers_subdomain" {
  description = "Your account's custom *.workers.dev subdomain."
  type        = string
}

variable "cloudflare_account_id" {
  description = "Your cloudflare account id."
  type        = string
}

variable "cloudflare_api_token" {
  description = "API token for the Cloudflare provider. Must have Workers, KV, and Queues permissions."
  type        = string
  sensitive   = true
}

variable "enable_redis" {
  description = "Set to true to create an ElastiCache Redis cluster."
  type        = bool
  default     = false
}

variable "redis_node_type" {
  description = "The instance size for the Redis nodes (e.g., cache.t4g.micro)."
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_engine_version" {
  description = "The version of the Redis engine to use."
  type        = string
  default     = "7.0" # Use a recent, stable version
}



variable "s3_backup_gir_transition_days" {
  description = "Number of days after which to transition S3 backup objects to Glacier Instant Retrieval."
  type        = number
  default     = 30
}

variable "s3_backup_expire_old_versions_days" {
  description = "Number of days after which to expire old (non-current) versions of S3 backup objects."
  type        = number
  default     = 365 # Expire old versions after one year
}

variable "cf_verify_secret" {
  description = "Shared secret string to verify traffic comes from Cloudflare (Production only)"
  type        = string
  sensitive   = true
  default     = "" # Can be empty for dev/staging
}

variable "cloudflare_zone_id" {
  description = "The Zone ID from the Cloudflare dashboard"
  type        = string
}

variable "ecs_task_cpu" {
  description = "CPU units for the App (256, 512, 1024, 2048). Default high for Prod, override for Dev."
  type        = string
  default     = "1024" # 1 vCPU - Good baseline for 2k users/instance
}

variable "ecs_task_memory" {
  description = "Memory for the App. Default high for Prod."
  type        = string
  default     = "2048" # 2 GB
}

variable "staging_active" {
  description = "Set to true to spin up Staging ECS tasks for testing. Set false to save compute costs."
  type        = bool
  default     = false
}

variable "min_capacity" {
  description = "Minimum number of tasks to run in the ECS service."
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of tasks to run in the ECS service."
  type        = number
  default     = 1
}

variable "webhook_secret" {
  description = "A secret string to secure the webhook endpoint that the worker calls when a game is processed."
  type        = string
  sensitive   = true
}
