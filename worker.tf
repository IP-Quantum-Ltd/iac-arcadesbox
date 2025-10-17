# This resource takes the BUNDLED Javascript file and uploads it to Cloudflare.
resource "cloudflare_workers_script" "game_cdn_worker" {
  count       = var.r2_bucket_is_public ? 0 : 1
  account_id  = var.r2_account_id
  script_name = "${var.app_name_prefix}-games-worker-${var.environment}-${var.infra_suffix}"

  # --- NEW: Use the bundled script content ---
  # This now points to the output of the 'wrangler' build step.
  #content = file("${path.module}/../../dist/game_gatekeeper.js") # Assumes the bundled file is in root /dist

  content = local.worker_script_content

  # --- NEW: Define the main module and compatibility date ---
  compatibility_date = "2025-07-27" # MUST match the date in wrangler.toml

  main_module = "game_gatekeeper.js"

  bindings = [
    {
      name        = "GAMES_BUCKET"
      type        = "r2_bucket"
      bucket_name = aws_s3_bucket.games_bucket.bucket
    },
    {
      name = "WORKER_JWT_SECRET"
      type = "secret_text"
      text = var.worker_jwt_secret
    },
    {
      name = "ALLOWED_ORIGINS"
      type = "secret_text"
      text = jsonencode(["https://${var.frontend_domain_name}", "https://${var.api_domain_name}"])
    }
  ]
}

# resource "cloudflare_workers_custom_domain" "games_cdn_domain" {
#   account_id  = var.r2_account_id
#   hostname    = var.games_cdn_domain_name
#   environment = var.environment
#   service     = cloudflare_workers_script.game_cdn_worker.script_name
# }

