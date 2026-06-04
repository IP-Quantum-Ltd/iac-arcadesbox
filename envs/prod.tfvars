infra_suffix = "v1"
environment  = "production"
aws_region   = "us-east-1"

frontend_domain_name   = "www.arcadesbox.com"
games_cdn_domain_name  = "cdn.arcadesbox.org"
ses_sending_domain     = "www.arcadesbox.com"
ses_from_email_address = "no-reply@arcadesbox.com"
ses_region             = "us-east-1"


# Domain Configuration
root_domain_name = "arcadesbox.com"
api_domain_name  = "api.arcadesbox.com"

# CNAME Targets (Get these from your Cloudflare account)
cloudflare_pages_cname_target = "arcadesbox.pages.dev"
r2_public_cname_target        = "cdn.arcadesbox.org"

cloudflare_workers_subdomain = "arcadesbox-prod.workers.dev"
cloudflare_account_id        = "6a174bfe8d474ce652234319a3be34fa"

# Sensitive values come from TF_VAR_* env (see GitHub Environment secrets):
#   r2_access_key_id, r2_secret_access_key, worker_jwt_secret,
#   cloudflare_api_token, cloudflare_zone_id, webhook_secret, cf_verify_secret

create_local_dev_user = false
r2_account_id         = "6a174bfe8d474ce652234319a3be34fa"

enable_redis    = true
redis_node_type = "cache.t4g.small"
github_branch   = "release"
github_repo     = "chareli"
github_org      = "IP-Quantum-Ltd"


app_name_prefix                    = "arcadesbox"
s3_backup_gir_transition_days      = 30
s3_backup_expire_old_versions_days = 365

staging_active  = false
ecs_task_cpu    = "2048"
ecs_task_memory = "4096"
min_capacity    = 1
max_capacity    = 70

# --- AI Agent ---
ai_agent_active    = true   # flip true after staging soak + real image push to prod ECR
ai_agent_cpu       = "2048" # 2 vCPU
ai_agent_memory    = "4096" # 4 GB — production headroom for Playwright + LangChain
ai_agent_image_tag = "placeholder"
