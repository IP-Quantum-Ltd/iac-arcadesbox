# ArcadesBox IaC — Runbook

Operational procedures for the recurring tasks the on-call DevOps engineer performs against this repo. Read [`../HANDOFF.md`](../HANDOFF.md) first — it explains the moving parts referenced here.

## Table of contents

- [Prerequisites and environment setup](#prerequisites-and-environment-setup)
- [Common Terraform operations](#common-terraform-operations)
  - [Planning a change](#planning-a-change)
  - [Applying via CI (the supported path)](#applying-via-ci-the-supported-path)
  - [Applying locally (break-glass)](#applying-locally-break-glass)
  - [Selecting a workspace](#selecting-a-workspace)
  - [Force-unlocking state](#force-unlocking-state)
- [Secrets Manager operations](#secrets-manager-operations)
  - [Populate or update application secrets](#populate-or-update-application-secrets)
  - [Populate backup-tool secrets](#populate-backup-tool-secrets)
  - [Populate AI agent secrets (when applicable)](#populate-ai-agent-secrets-when-applicable)
  - [Inspect a secret](#inspect-a-secret)
  - [Delete an orphaned key](#delete-an-orphaned-key)
- [ECS operations](#ecs-operations)
  - [Force a redeploy of the app service](#force-a-redeploy-of-the-app-service)
  - [Open a shell in a running task (non-prod only)](#open-a-shell-in-a-running-task-non-prod-only)
  - [Tail application logs](#tail-application-logs)
  - [Run the backup tool on demand](#run-the-backup-tool-on-demand)
- [DNS and TLS operations](#dns-and-tls-operations)
  - [Roll the ACM certificate](#roll-the-acm-certificate)
  - [Add a new SES sending domain](#add-a-new-ses-sending-domain)
- [Worker / R2 / Queues](#worker--r2--queues)
  - [Inspect what wrangler-deployed code is running](#inspect-what-wrangler-deployed-code-is-running)
  - [Drain the dead-letter queue](#drain-the-dead-letter-queue)
- [Toggling environment behaviors](#toggling-environment-behaviors)
  - [Enable Redis on a non-prod env](#enable-redis-on-a-non-prod-env)
  - [Spin staging up or down](#spin-staging-up-or-down)
  - [Activate the AI agent service](#activate-the-ai-agent-service)
  - [Switch the WAF allow-secret](#switch-the-waf-allow-secret)
- [Onboarding a new environment](#onboarding-a-new-environment)
- [Decommissioning an environment](#decommissioning-an-environment)
- [Disaster scenarios](#disaster-scenarios)
  - [The Terraform state is corrupted](#the-terraform-state-is-corrupted)
  - [Someone accidentally `terraform destroy`'d](#someone-accidentally-terraform-destroyd)
  - [The R2 bucket events stopped firing](#the-r2-bucket-events-stopped-firing)
  - [The ALB is returning 503 / target group unhealthy](#the-alb-is-returning-503--target-group-unhealthy)

---

## Prerequisites and environment setup

You need:

- AWS CLI configured for the account that owns `arcadebox-prod-terraform-state`. Either use SSO (`aws sso login --profile <profile>` then export `AWS_PROFILE=<profile>`) or static creds from a properly scoped IAM user.
- Terraform `>= 1.12.0`. Repo is currently working on `1.14.0` per CI.
- Cloudflare API token exported as `CLOUDFLARE_API_TOKEN` (or supply via tfvars / `TF_VAR_cloudflare_api_token`). Token needs Workers, KV, Queues, R2, DNS write scopes for the zone.
- The four `envs/*.tfvars` files placed under `envs/` (they're gitignored — get them from the previous engineer).
- `jq` and `bash` for the secrets-upload script.
- (Optional) `wrangler` (`npm i -g wrangler`) if you want to test workers locally.

Quick verification:

```bash
aws sts get-caller-identity                # should show the right account
aws s3 ls s3://arcadebox-prod-terraform-state/   # should list env:/ prefixes
terraform version                          # should be >= 1.12.0
```

---

## Common Terraform operations

### Planning a change

```bash
# Always select workspace first.
terraform workspace select development

# Plan with the matching tfvars.
terraform plan -var-file=envs/dev.tfvars -out=tfplan
```

Repeat with `staging` / `production` as needed. Read the plan output carefully — even a one-line variable change can touch many resources because of how naming interpolation cascades.

### Applying via CI (the supported path)

1. Open a PR to `dev`, `staging`, or `main` (matching the target environment).
2. The `terraform-plan` job posts a sticky comment with the plan. Review it.
3. Get a reviewer to approve. Squash-merge the PR.
4. The `terraform-apply` job runs automatically on the push that the merge creates.
5. For `main`, GitHub Environment protection requires manual approval before apply runs. Approve in the Actions UI.

If the apply fails midway, the state may be partially updated. Re-run the workflow from the Actions UI; the next plan will show what's left.

### Applying locally (break-glass)

Only when CI is broken or you need to fix something the pipeline can't.

```bash
terraform workspace select <env>
terraform plan -var-file=envs/<env>.tfvars -out=tfplan
terraform apply tfplan
```

Don't apply without `-out=tfplan`; you'll race against any concurrent CI run.

### Selecting a workspace

```bash
terraform workspace list           # see what exists
terraform workspace show           # see what's currently selected
terraform workspace select <name>  # switch
terraform workspace new <name>     # create (if onboarding new env)
terraform workspace delete <name>  # destroy state for an env (after destroying resources)
```

### Force-unlocking state

If a CI job crashed and left a DynamoDB lock:

```bash
# The error message will include a LockID UUID.
terraform force-unlock <LOCK_ID>
```

Don't make this routine. If you do it twice in a week, find the underlying cause.

---

## Secrets Manager operations

### Populate or update application secrets

```bash
# Edit .env.staging locally with the desired values, then:
bash scripts/upload-secrets.sh \
  .env.staging \
  arcadesbox/staging/v1/application-secrets \
  eu-central-1
```

To preview without writing:

```bash
DRY_RUN=true bash scripts/upload-secrets.sh \
  .env.staging \
  arcadesbox/staging/v1/application-secrets \
  eu-central-1
```

Naming pattern: `arcadesbox/<environment>/<infra_suffix>/application-secrets`. Region must match the env (`eu-central-1` for dev/staging/test, `us-east-1` for prod).

**The script does not delete keys that disappear from the .env file.** If you remove a key from `.env`, also delete it from the Secret Manager value (see [Delete an orphaned key](#delete-an-orphaned-key)).

After upload, restart the ECS service so tasks pick up the new values:

```bash
aws ecs update-service \
  --cluster arcadesbox-ecs-cluster-staging-v1 \
  --service arcadesbox-service-staging-v1 \
  --force-new-deployment \
  --region eu-central-1
```

### Populate backup-tool secrets

```bash
bash scripts/upload-secrets.sh \
  .env.backup.staging \
  arcadesbox/staging/v1/backup-tool-secrets \
  eu-central-1
```

The backup task picks up secrets at next scheduled run (daily 02:00 UTC), or you can run it on demand (see [Run the backup tool on demand](#run-the-backup-tool-on-demand)).

### Populate AI agent secrets (when applicable)

When the in-flight AI agent work has landed:

```bash
bash scripts/upload-secrets.sh \
  .env.ai \
  arcadesbox/staging/v1/ai-agent-secrets \
  eu-central-1
```

Required keys are listed in `secrets_ai_agent.tf:7-19`.

### Inspect a secret

```bash
aws secretsmanager get-secret-value \
  --secret-id arcadesbox/staging/v1/application-secrets \
  --region eu-central-1 \
  --query SecretString --output text | jq .
```

Pipe to `jq` to format. **Don't paste output anywhere unsanitized.**

### Delete an orphaned key

```bash
# Get current secret as JSON
aws secretsmanager get-secret-value \
  --secret-id arcadesbox/staging/v1/application-secrets \
  --region eu-central-1 \
  --query SecretString --output text > /tmp/secret.json

# Edit /tmp/secret.json — remove the unwanted key

# Push back
aws secretsmanager put-secret-value \
  --secret-id arcadesbox/staging/v1/application-secrets \
  --region eu-central-1 \
  --secret-string file:///tmp/secret.json

shred -u /tmp/secret.json   # cleanup
```

---

## ECS operations

### Force a redeploy of the app service

Useful after rotating Secrets Manager values, or when you want to pick up a fresh `:latest` image:

```bash
aws ecs update-service \
  --cluster arcadesbox-ecs-cluster-<env>-v1 \
  --service arcadesbox-service-<env>-v1 \
  --force-new-deployment \
  --region <region>
```

### Open a shell in a running task (non-prod only)

ECS Exec is enabled in dev/staging/test. Find a running task:

```bash
TASK_ARN=$(aws ecs list-tasks \
  --cluster arcadesbox-ecs-cluster-staging-v1 \
  --service-name arcadesbox-service-staging-v1 \
  --region eu-central-1 \
  --query 'taskArns[0]' --output text)

aws ecs execute-command \
  --cluster arcadesbox-ecs-cluster-staging-v1 \
  --task "$TASK_ARN" \
  --container arcadesbox-ecs-backend-staging-server-v1 \
  --command "/bin/sh" \
  --interactive \
  --region eu-central-1
```

To enable in production temporarily, edit `local.enable_ecs_exec` in `locals.tf`, run `terraform apply`, do your debugging, then revert.

### Tail application logs

```bash
aws logs tail /ecs/arcadesbox-staging-v1 \
  --since 10m --follow \
  --region eu-central-1
```

For a Logs Insights query (the same one the dashboard uses):

```bash
aws logs start-query \
  --log-group-name /ecs/arcadesbox-staging-v1 \
  --start-time $(date -u -d '15 min ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, level, message, requestId | sort @timestamp desc | limit 200' \
  --region eu-central-1
# … then aws logs get-query-results --query-id <id-from-above>
```

### Run the backup tool on demand

```bash
aws ecs run-task \
  --cluster arcadesbox-ecs-cluster-staging-v1 \
  --task-definition arcadesbox-backup-tool-staging-v1 \
  --launch-type FARGATE \
  --network-configuration 'awsvpcConfiguration={subnets=[<subnet-id>],securityGroups=[<sg-id>],assignPublicIp=ENABLED}' \
  --region eu-central-1
```

Get subnet/SG IDs from `terraform output` or the AWS console. For prod, set `assignPublicIp=DISABLED` and use the private subnets (the schedule's network config in `scheduler.tf:79-83` is the source of truth).

Watch logs at `/ecs/arcadesbox-backup-tool-staging-v1`.

---

## DNS and TLS operations

### Roll the ACM certificate

ACM auto-renews validated certs. If you ever need to force a roll:

```bash
terraform plan -var-file=envs/<env>.tfvars -replace=aws_acm_certificate.api_cert
# Review carefully — this will recreate the cert and the Cloudflare validation records.
terraform apply ...
```

The 60s `time_sleep` will pause the apply. The HTTPS listener is set to `create_before_destroy` on the cert, so there should be no downtime, but verify in plan output.

### Add a new SES sending domain

If you ever add a new SES domain (e.g., for a new product line):

1. Add a new `aws_ses_domain_identity` and `aws_ses_domain_dkim` in `ses.tf` (or a new file).
2. Add the corresponding `cloudflare_dns_record` for the SES TXT and 3× DKIM CNAMEs.
3. Apply.
4. Verify in SES console (status should go from `Pending` to `Verified` once DNS propagates — usually a few minutes).
5. If you're using the new domain to send transactional email from the app, update `ses_sending_domain` and `ses_from_email_address` in the relevant tfvars and re-apply, then re-deploy the ECS service so it picks up the new env vars.

---

## Worker / R2 / Queues

### Inspect what wrangler-deployed code is running

```bash
# List all worker scripts in the account
wrangler deployments list --name arcadesbox-games-zip-processor-staging-v1
```

Or via Cloudflare dashboard → Workers & Pages → the script → Deployments tab.

The Terraform-deployed placeholder content lives in `locals.tf`. If wrangler has never deployed real code, the worker returns 503 with a "deploy code via wrangler" message.

### Drain the dead-letter queue

```bash
# List pending messages
wrangler queues consumer pull arcadesbox-game-zip-dlq-staging-v1
```

To consume them: write a one-off worker that reads from the DLQ and either retries or logs to S3. The chareli repo may already have one — check there before writing new code.

---

## Toggling environment behaviors

### Enable Redis on a non-prod env

Edit `envs/<env>.tfvars`:

```hcl
enable_redis = true
```

Apply. Redis takes ~10 minutes to provision. The app picks up `REDIS_HOST` / `REDIS_PORT` env vars on next task start. If `REDIS_CACHE_ENABLED` in the Secrets Manager value is also `true`, the app will start using the cache.

### Spin staging up or down

To save money when staging isn't in use, edit `envs/staging.tfvars`:

```hcl
staging_active = false
```

Apply. ECS desired_count goes to 0 and tasks stop. The infra (ALB, secrets, etc.) stays. To bring it back, set `staging_active = true` and apply.

### Activate the AI agent service

Once the in-flight work in [§9 of HANDOFF.md](../HANDOFF.md#9-in-flight-work-on-cloudflare-dns-branch) is merged and a real image is in ECR:

1. Push the AI agent image to `arcadesbox-ai-agent-<env>-v1` ECR repo with a tag.
2. Edit `envs/<env>.tfvars`:
   ```hcl
   ai_agent_active    = true
   ai_agent_image_tag = "<your-tag>"
   ```
3. Apply. ECS will pull the image and start a task.
4. Verify connectivity from the main app: `aws ecs execute-command` into a backend task, then `curl http://ai-agent:8000/health`.

### Switch the WAF allow-secret

`cf_verify_secret` is the secret token Cloudflare's transform rule injects into the `x-origin-verify` header. To rotate:

1. Generate a new random secret.
2. Edit `envs/prod.tfvars`: `cf_verify_secret = "<new-value>"`.
3. **Add the new secret to the Cloudflare transform rule first** (so both old and new are accepted briefly).
4. `terraform apply` — WAF is updated to accept the new secret.
5. Once you've verified prod is healthy, remove the old secret from the Cloudflare transform rule.

If you don't update Cloudflare's rule first, every request is blocked by WAF until you do.

---

## Onboarding a new environment

If you ever need a fourth env (say, `qa`):

1. **Create the workspace state slot.** `terraform workspace new qa`.
2. **Create `envs/qa.tfvars`** based on `envs/dev.tfvars`. Choose unique domains and a unique `infra_suffix` if you want isolated resources.
3. **Add a branch handler** to `.github/workflows/terraform.yml`:
   ```yaml
   case "$BRANCH" in
     ...
     qa)
       echo "environment=qa" >> $GITHUB_OUTPUT
       echo "workspace=qa" >> $GITHUB_OUTPUT
       echo "tfvars=envs/qa.tfvars" >> $GITHUB_OUTPUT
       ;;
     ...
   ```
4. **Create the matching GitHub Environment** in repo settings, set protection rules.
5. **Create the qa branch**: `git checkout -b qa main; git push -u origin qa`.
6. **Configure DNS** (a Cloudflare zone or subdomain). The frontend, api, and games CDN domains all need to exist as zones / subzones Cloudflare can write to.
7. **Apply.** First apply provisions the IAM roles; subsequent secrets-upload populates Secrets Manager; then redeploy ECS.
8. **Update `HANDOFF.md`** with the new env in [§4 of HANDOFF.md](../HANDOFF.md#4-environments-and-the-workspace-model).

---

## Decommissioning an environment

```bash
terraform workspace select <env>
terraform destroy -var-file=envs/<env>.tfvars
```

Caveats:
- The S3 archive bucket has Object Lock COMPLIANCE mode; it cannot be destroyed until all objects' retention windows expire. `terraform destroy` will fail. Plan ahead — empty the bucket via lifecycle expiration first, or accept that the bucket will linger.
- `force_destroy = true` on the ALB logs bucket means logs are silently deleted. If you want to preserve them, copy them out first.
- The Cloudflare DNS records are destroyed alongside, so you'll lose any related CDN / pages / mail config tied to those records. Restore from Cloudflare's audit log if needed.
- After destroy: `terraform workspace delete <env>` to drop the state slot.

---

## Disaster scenarios

### The Terraform state is corrupted

S3 versions every state object. Roll back:

```bash
aws s3api list-object-versions \
  --bucket arcadebox-prod-terraform-state \
  --prefix env:/<env>/arcadesbox/test/terraform.tfstate \
  --region us-east-1
# Find the prior version id, then:
aws s3api copy-object \
  --bucket arcadebox-prod-terraform-state \
  --copy-source 'arcadebox-prod-terraform-state/env:/<env>/arcadesbox/test/terraform.tfstate?versionId=<prior-version-id>' \
  --key 'env:/<env>/arcadesbox/test/terraform.tfstate' \
  --region us-east-1
```

Then `terraform plan` to see drift between state and reality.

### Someone accidentally `terraform destroy`'d

If state still has the resources:
- Try `terraform plan` immediately to see what's gone.
- For each missing resource, you can either re-apply (Terraform recreates) or `terraform import` from a backup.

If both state and resources are gone:
- Restore state from S3 versioning (above).
- For Cloudflare-side resources, check Cloudflare's audit log to see whether the records still exist; if not, expect to re-apply.
- For S3 archive bucket: it's Object Lock COMPLIANCE; the *bucket* can't actually be destroyed until objects' retention expires. Look in the AWS console — it's probably still there.
- For data: ECS task definitions can be recreated; ECS services can be recreated; secrets can be re-uploaded. The actual *data* in S3 archive bucket and R2 buckets is the only irreplaceable thing — and S3 versioning + replication should have made copies.

### The R2 bucket events stopped firing

- Check the Cloudflare dashboard: R2 → Bucket → Event notifications. The Terraform-managed rule should be visible.
- Check the queue: `wrangler queues info arcadesbox-game-zip-queue-<env>-v1`. If consumer is missing, the worker (chareli-deployed) needs redeploying with `wrangler deploy`.
- Check that `temp-games/` prefix is being used by uploads (a misconfigured backend that uploads to a different prefix won't fire events).

### The ALB is returning 503 / target group unhealthy

```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $(aws elbv2 describe-target-groups \
    --names arcadesbox-tg-<env>-v1 \
    --query 'TargetGroups[0].TargetGroupArn' --output text \
    --region <region>) \
  --region <region>

# Check ECS service events
aws ecs describe-services \
  --cluster arcadesbox-ecs-cluster-<env>-v1 \
  --services arcadesbox-service-<env>-v1 \
  --region <region> \
  --query 'services[0].events[0:10]'

# Check task logs for the most recent failure
aws logs tail /ecs/arcadesbox-<env>-v1 --since 30m --region <region>
```

Common causes:
- App can't start because Secrets Manager value is missing a key the app expects → fix the secret, force-redeploy.
- App can't reach Postgres / Mongo → check VPC connectivity, security group egress rules, DB credentials.
- App's `/api/health` endpoint changed → check chareli backend; re-align target group health check path in `alb.tf:23-33`.
- Image pull failures → ECR auth issues, image doesn't exist, or task execution role missing ECR perms.

---

*Last updated: 2026-05-07*
