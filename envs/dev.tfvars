infra_suffix = "v1"
environment  = "development"
aws_region   = "eu-central-1"

frontend_domain_name   = "dev.arcadesbox.com"
games_cdn_domain_name  = "games.dev.arcadesbox.com"
ses_sending_domain     = "dev.arcadesbox.com"
ses_from_email_address = "no-reply@dev.arcadesbox.com"
ses_region             = "eu-central-1"


# Domain Configuration
root_domain_name = "arcadesbox.com"
api_domain_name  = "api-dev.arcadesbox.com"

# CNAME Targets (Get these from your Cloudflare account)
cloudflare_pages_cname_target = "arcadesbox-dev.pages.dev"
r2_public_cname_target        = "dev.cdn.arcadesbox.org"

cloudflare_workers_subdomain = "arcadesbox-prod.workers.dev"
cloudflare_account_id        = "6a174bfe8d474ce652234319a3be34fa"

# Sensitive values come from TF_VAR_* env (see GitHub Environment secrets):
#   r2_access_key_id, r2_secret_access_key, worker_jwt_secret,
#   cloudflare_api_token, cloudflare_zone_id, webhook_secret

create_local_dev_user = false
r2_account_id         = "6a174bfe8d474ce652234319a3be34fa"

enable_redis  = true
github_branch = "dev"
github_repo   = "chareli"
github_org    = "IP-Quantum-Ltd"

app_name_prefix                    = "arcadesbox"
s3_backup_gir_transition_days      = 30
s3_backup_expire_old_versions_days = 365
staging_active                     = false

# --- AI Agent ---
ai_agent_active    = false
ai_agent_cpu       = "512"
ai_agent_memory    = "2048"
ai_agent_image_tag = "placeholder"
