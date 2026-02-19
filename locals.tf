locals {
  # Placeholder worker script — deployed on first terraform apply.
  # The real worker code is deployed separately via `wrangler deploy` from the app repo.
  worker_placeholder_script = <<-EOF
    export default {
      async fetch(request, env, ctx) {
        return new Response("Worker provisioned by Terraform. Deploy code via wrangler.", { status: 503 });
      }
    };
  EOF

  enable_ecs_exec = var.environment != "production" && var.environment != "prod"
}
