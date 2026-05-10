# -----------------------------------------------------------------------------
# Execution role: pulls image, fetches secrets, writes logs.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ai_agent_task_execution" {
  name               = "${var.app_name_prefix}-ai-agent-task-execution-${var.environment}-${var.infra_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role_policy.json
}

data "aws_iam_policy_document" "ai_agent_task_execution_secrets_policy_doc" {
  statement {
    sid       = "AIAgentSecretsRead"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.ai_agent_secrets.arn]
  }
}

resource "aws_iam_policy" "ai_agent_task_execution_secrets_policy" {
  name   = "${var.app_name_prefix}-ai-agent-execution-secrets-policy-${var.environment}-${var.infra_suffix}"
  policy = data.aws_iam_policy_document.ai_agent_task_execution_secrets_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "ai_agent_task_execution_managed_policy" {
  role       = aws_iam_role.ai_agent_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "ai_agent_task_execution_secrets_attachment" {
  role       = aws_iam_role.ai_agent_task_execution.name
  policy_arn = aws_iam_policy.ai_agent_task_execution_secrets_policy.arn
}

# -----------------------------------------------------------------------------
# Task role: identity the running container uses. AI agent talks to external
# HTTPS endpoints (OpenAI, Anthropic, MongoDB Atlas, LangSmith), the main
# backend over Service Connect, and Cloudflare R2 for Stage 0 artifact storage.
# R2 auth uses access keys from Secrets Manager (not IAM), so the role still
# carries no inline policy. ECS Exec is attached for non-prod debugging.
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ai_agent_task" {
  name               = "${var.app_name_prefix}-ai-agent-task-role-${var.environment}-${var.infra_suffix}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ai_agent_task_ssm" {
  count      = local.enable_ecs_exec ? 1 : 0
  role       = aws_iam_role.ai_agent_task.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
