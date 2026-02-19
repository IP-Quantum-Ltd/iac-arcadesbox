# --- Cloudflare Worker (Infrastructure Only) ---
# This resource provisions the worker shell with its bindings and settings.
# The actual worker CODE is deployed separately via `wrangler deploy` from the app repo's CI/CD.
# On first `terraform apply`, a placeholder script is uploaded. It gets overwritten on first deploy.

resource "cloudflare_workers_script" "game_zip_processor_worker" {
  account_id  = var.cloudflare_account_id
  script_name = "${var.app_name_prefix}-games-zip-processor-${var.environment}-${var.infra_suffix}"

  # Placeholder content — overwritten by wrangler deploy from the app repo
  content     = local.worker_placeholder_script
  main_module = "index.js"

  compatibility_date  = "2026-02-17"
  compatibility_flags = ["nodejs_compat"]

  # Preserve bindings when code is deployed externally via wrangler
  keep_bindings = ["plain_text", "secret_text", "kv_namespace", "r2_bucket", "queue"]

  bindings = [
    # --- R2 Bucket ---
    {
      name        = "GAMES_BUCKET"
      type        = "r2_bucket"
      bucket_name = aws_s3_bucket.games_bucket.bucket
    },
    # --- KV Namespace ---
    {
      name         = "GAME_STATUS"
      type         = "kv_namespace"
      namespace_id = cloudflare_workers_kv_namespace.game_status.id
    },
    # --- Queues ---
    {
      name       = "GAME_ZIP_QUEUE"
      type       = "queue"
      queue_name = cloudflare_queue.game_zip_queue.queue_name
    },
    {
      name       = "GAME_ZIP_DLQ"
      type       = "queue"
      queue_name = cloudflare_queue.game_zip_dlq.queue_name
    },
    # --- Environment Variables ---
    {
      name = "BACKEND_WEBHOOK_URL"
      type = "plain_text"
      text = "https://${var.api_domain_name}/api/internal/game-processed"
    }
  ]

  observability = {
    enabled            = true
    head_sampling_rate = 0.1
    logs = {
      enabled            = true
      invocation_logs    = true
      destinations       = ["cloudflare"]
      head_sampling_rate = 0.1
      persist            = true
    }
  }

  lifecycle {
    ignore_changes = [content]
  }
}
