# Secrets Manager shell for the AI agent. Values are seeded manually via
# AWS CLI/Console — Terraform owns the name and ARN only.
#
# Expected keys (seed manually before first task starts):
#   ARCADE_API_BASE_URL, ARCADE_API_TOKEN,
#   AI_PROVIDER, OPENAI_API_KEY, ANTHROPIC_API_KEY,
#   PRIMARY_LLM_MODEL, SECONDARY_LLM_MODEL, EMBEDDING_MODEL, OPENAI_WEB_SEARCH_MODEL,
#   DATABASE_URL, DB_HOST, DB_PORT, DB_USERNAME, DB_PASSWORD, DB_DATABASE,
#   MONGODB_URL, MONGODB_DB_NAME, MONGODB_RAG_COLLECTION,
#   MONGODB_VECTOR_INDEX, MONGODB_EVALUATION_COLLECTION,
#   CLIENT_URL,
#   BROWSER_VIEWPORT_WIDTH, BROWSER_VIEWPORT_HEIGHT,
#   EXTERNAL_PAGE_TIMEOUT_MS, INTERNAL_PAGE_TIMEOUT_MS,
#   WEBHOOK_SECRET,
#   CLOUDFLARE_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_PUBLIC_URL,
#   CRON_INTERVAL_MINUTES, MAX_PLAN_REVISIONS, MAX_DRAFT_REVISIONS,
#   JOB_RETENTION_HOURS, STAGE0_REQUIRED_CANDIDATES,
#   STAGE0_MAX_SEARCH_RESULTS, STAGE0_CANDIDATE_CAPTURE_TIMEOUT_SECONDS,
#   LANGCHAIN_TRACING_V2, LANGCHAIN_API_KEY, LANGCHAIN_PROJECT, LANGCHAIN_ENDPOINT,
#   LANGSMITH_TRACING, LANGSMITH_API_KEY, LANGSMITH_PROJECT, LANGSMITH_ENDPOINT
resource "aws_secretsmanager_secret" "ai_agent_secrets" {
  name        = "${var.app_name_prefix}/${var.environment}/${var.infra_suffix}/ai-agent-secrets"
  description = "Consolidated secrets for the ArcadesBox AI agent (${var.environment}-${var.infra_suffix})"
}

output "ai_agent_secrets_arn" {
  description = "ARN of the AI agent secrets bundle."
  value       = aws_secretsmanager_secret.ai_agent_secrets.arn
}
