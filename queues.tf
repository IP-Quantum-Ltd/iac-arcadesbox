# --- Cloudflare Queues ---
# Provisions the message queues for async game processing.
# The consumer/producer bindings are configured in the worker's wrangler.toml.

# Dead Letter Queue - receives messages that fail processing after max retries
resource "cloudflare_queue" "game_zip_dlq" {
  account_id = var.cloudflare_account_id
  queue_name = "${var.app_name_prefix}-game-zip-dlq-${var.environment}-${var.infra_suffix}"

  settings = {
    delivery_paused          = false
    message_retention_period = 86400 # 24 hours - gives time to investigate failures
  }
}

# Main processing queue - game ZIP uploads are sent here for async processing
resource "cloudflare_queue" "game_zip_queue" {
  account_id = var.cloudflare_account_id
  queue_name = "${var.app_name_prefix}-game-zip-queue-${var.environment}-${var.infra_suffix}"

  settings = {
    delivery_paused          = false
    message_retention_period = 43200 # 12 hours
  }
}
