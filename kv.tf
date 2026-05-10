# --- Cloudflare Workers KV Namespace ---
# Used by workers for status tracking and key-value storage.
# The actual KV data operations happen in the worker code, not here.

resource "cloudflare_workers_kv_namespace" "game_status" {
  account_id = var.cloudflare_account_id
  title      = "${var.app_name_prefix}-game-status-${var.environment}-${var.infra_suffix}"
}
