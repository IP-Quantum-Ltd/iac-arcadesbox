# ArcadesBox IaC — Engineering Handoff

> **Author:** Christian Koranteng (DevOps Lead, departing 2026-05-08)
> **Date:** 2026-05-07
> **Audience:** Incoming DevOps / Platform engineer + reviewing staff engineer
> **Status of repo at handoff:** branch `cloudflare-dns` has uncommitted in-flight work for an "AI agent" ECS service. See [§9](#9-in-flight-work-on-cloudflare-dns-branch).

This document is the single source of truth for the ArcadesBox infrastructure repo. The existing `README.md` is a getting-started guide for a local engineer and is **partially out of date** (see [§10](#10-knownproblemswithexistingreadme)). Treat this file as authoritative; treat the README as flavour.

The companion file [`docs/RUNBOOK.md`](docs/RUNBOOK.md) contains copy-pasteable procedures for the operations you'll perform most often.

---

## Table of contents

1. [10-minute first read (TL;DR)](#1-10-minute-first-read-tldr)
2. [What this repo manages](#2-what-this-repo-manages)
3. [Repository layout, file by file](#3-repository-layout-file-by-file)
4. [Environments and the workspace model](#4-environments-and-the-workspace-model)
5. [State, locking, and the backend](#5-state-locking-and-the-backend)
6. [CI/CD pipeline (.github/workflows/terraform.yml)](#6-cicd-pipeline-githubworkflowsterraformyml)
7. [Secrets, tfvars, and configuration](#7-secrets-tfvars-and-configuration)
8. [IAM roles and trust relationships](#8-iam-roles-and-trust-relationships)
9. [In-flight work on `cloudflare-dns` branch](#9-in-flight-work-on-cloudflare-dns-branch)
10. [Known problems with the existing README](#10-known-problems-with-the-existing-readme)
11. [Landmines, surprises, and gotchas](#11-landmines-surprises-and-gotchas)
12. [Open questions for the next engineer](#12-open-questions-for-the-next-engineer)
13. [Recommended first-week plan](#13-recommended-first-week-plan)
14. [External systems and contacts](#14-external-systems-and-contacts)

---

## 1. 10-minute first read (TL;DR)

You inherited the Terraform IaC for **ArcadesBox** (a.k.a. internal codename **chareli**). It provisions:

- An **AWS** stack (VPC, ECS Fargate cluster, ALB, ECR, Secrets Manager, S3, ElastiCache Redis, SES, CloudWatch, EventBridge, WAF) in `eu-central-1` for non-prod and `us-east-1` for prod.
- A **Cloudflare** stack (DNS for `arcadesbox.com` + `arcadesbox.org`, R2 buckets, Workers, KV, Queues) on Cloudflare account `6a174bfe8d474ce652234319a3be34fa`.
- IAM roles for two GitHub OIDC trust relationships:
  - **App-deploy** (`chareli` backend repo) → ECR push + ECS service update
  - **Terraform CI** (this repo) → `AdministratorAccess`

State lives in S3 bucket `arcadebox-prod-terraform-state` (note the **single-r typo**, this is intentional) with locking via DynamoDB table `arcadesbox-prod-terraform-locks`. One key path (`arcadesbox/test/terraform.tfstate`) is shared across all environments via Terraform workspaces (`development`, `staging`, `production`).

**Five things to read carefully before touching anything:**

1. **§7 (secrets/tfvars).** `envs/*.tfvars` are gitignored *and* referenced by CI. They contain hardcoded API tokens and webhook secrets. The next engineer needs a plan to (a) supply tfvars to CI, (b) rotate the leaked-on-disk secrets, and (c) move them to a real secret store.
2. **§6 (CI/CD).** The pipeline at `.github/workflows/terraform.yml` was added in commit `2cc6c91` on 2026-04-30 and **has never run end-to-end** as far as I know. The `terraform-apply` job uses GitHub Actions versions (`actions/checkout@v6`, `aws-actions/configure-aws-credentials@v6`, `actions/download-artifact@v8`) that **don't exist** as of writing. Plan job versions are correct.
3. **§9 (in-flight AI agent work).** Six new files (`ecr_ai_agent.tf`, `ecs_ai_agent.tf`, `iam_ai_agent.tf`, `secrets_ai_agent.tf`, `sg_ai_agent.tf`, `service_discovery.tf`) and five modified files (`alarms.tf`, `ecs.tf`, `iam_github.tf`, `outputs.tf`, `variables.tf`) form a single change set on local `cloudflare-dns`. The modified files reference resources defined in the untracked files; the change is atomic. Don't `git stash` it casually.
4. **§11 (landmines).** Wrangler owns Worker code and queue consumer; Terraform owns Worker shell and queue. The Worker resource has `lifecycle.ignore_changes = [content]`. Don't `terraform import` or refactor the worker without understanding this dual-management model.
5. **§5 (state).** Terraform workspaces multiplex one S3 key for three environments. Destroying the workspace, not the state file, is the way to tear an env down. There is **no separate Terraform state for prod**; misconfigured workspace selection in CI can apply prod plans to dev or vice versa.

---

## 2. What this repo manages

This repo is the lower half of the ArcadesBox stack. It does **not** contain application code. The application code (Express backend + React frontend) lives in **`github.com/IP-Quantum-Ltd/chareli`** — note the org is `IP-Quantum-Ltd`, **not** `Really-Great-Tech` as the README claims. This repo lives at `github.com/Really-Great-Tech/iac-arcadesbox` (correct in remote, sometimes mis-stated in docs).

**AWS resources provisioned (eu-central-1 dev/staging/test, us-east-1 prod):**

| Domain | Resources | Files |
|---|---|---|
| Networking | VPC `10.0.0.0/16`, 2 public + 2 private subnets, IGW, NAT GW (prod-only), S3 gateway endpoint, route tables, ALB SG, ECS SG | `networking.tf`, `networking_s3_endpoint.tf` |
| Compute | ECS Fargate cluster, capacity providers (FARGATE + FARGATE_SPOT), main app service + task def, ECR repos for `chareli-server` + `backup-tool` (+ `ai-agent` in-flight) | `ecs.tf`, `ecr.tf`, `ecr_ai_agent.tf` |
| Autoscaling | App Auto Scaling targets + 3 target-tracking policies (CPU 60%, memory 60%, ALB RPS=1000) — non-prod only | `ecs_autoscaling.tf` |
| Backups | EventBridge schedule (daily 02:00 UTC), backup-tool ECS task, S3 backup bucket (Glacier-IR lifecycle), S3 archive bucket (Object Lock + Deep Archive), DynamoDB job-lock table, S3→S3 replication | `ecs_backup.tf`, `scheduler.tf`, `s3.tf`, `s3_archive.tf`, `locking.tf` |
| Load balancing | Internet-facing ALB, target group `:5000`, HTTP→HTTPS redirect, HTTPS listener with ACM cert | `alb.tf`, `acm.tf` |
| TLS | ACM cert for API domain (DNS-validated via Cloudflare), 60s sleep for replication | `acm.tf` |
| DNS (Cloudflare) | Root `@` (prod-only, dummy IP for redirect), API CNAME to ALB, frontend CNAME to Pages, ACM validation records, SES domain TXT + DKIM CNAMEs, SPF + 5× SendGrid CNAMEs (prod-only) | `dns.tf`, `acm.tf`, `ses.tf` |
| Email | SES domain identity + DKIM, SES email identity for sender address | `ses.tf` |
| Secrets | Two AWS Secrets Manager shells (`application-secrets`, `backup-tool-secrets`) provisioned by Terraform; **values populated manually** via `scripts/upload-secrets.sh` | `secrets.tf`, `scripts/upload-secrets.sh` |
| Cache | ElastiCache Redis replication group (parameter group `noeviction`), subnet group, dedicated SG | `elasticache.tf` |
| Observability | CloudWatch dashboard (4 standard widgets + 2 conditional Redis widgets + 1 logs widget), 4 alarms (5xx, latency, ECS CPU, ECS memory), 2 Redis alarms per node, SNS topic for alerts | `dashboard.tf`, `alarms.tf` |
| Edge security | WAFv2 on ALB requiring `x-origin-verify` header — **production-only** | `waf.tf` |
| IAM (ECS) | Task execution role + task role + custom secrets policy + SES policy + (conditional) ECS Exec via SSM | `iam_ecs.tf` |
| IAM (GitHub OIDC) | Two roles: app-deploy (ECR/ECS-scoped) and terraform-CI (AdministratorAccess) | `iam_github.tf`, `iam_github_terraform.tf` |
| IAM (local dev) | Optional dev IAM user with Secrets Manager + SES read | `iam_local_dev_user.tf` |

**Cloudflare resources provisioned:**

| Domain | Resources | Files |
|---|---|---|
| R2 | Two buckets — `*-games-cdn-*` (public games) and `*-r2-backup-*` (mirror of S3 backup), both via S3-compatible API alias provider | `r2.tf` |
| R2 events | Bucket event notification on `temp-games/*.zip` PutObject → game-zip queue | `r2.tf` |
| Workers | Single Worker `*-games-zip-processor-*` with R2 + KV + Queues bindings; placeholder script (overwritten by wrangler from chareli repo) | `worker.tf`, `locals.tf` |
| KV | One namespace `*-game-status-*` for worker status tracking | `kv.tf` |
| Queues | `game_zip_queue` + `game_zip_dlq` (12h / 24h retention). **Queue consumer is owned by wrangler, not Terraform** (see comment in `queues.tf:1-5`) | `queues.tf` |

**What's intentionally not here:**
- Application Docker images (built and pushed from `chareli` repo's CI)
- Cloudflare Worker code (deployed via `wrangler deploy` from `chareli` repo's CI)
- Database (Postgres/MongoDB are provisioned outside Terraform — likely managed services that pre-date this stack; see [§12](#12-open-questions-for-the-next-engineer))
- Cloudflare Pages frontend deployments (Pages config is outside Terraform)
- Backup tool Docker image build (image is consumed at `:latest`; build pipeline is unknown to me — likely chareli repo)

---

## 3. Repository layout, file by file

| File | Purpose / what to know |
|---|---|
| `README.md` | Original onboarding doc. Partially outdated — see [§10](#10-known-problems-with-the-existing-readme). |
| `VARIABLES.md` | Reference table of variables. Out of date: missing `webhook_secret`, `cloudflare_api_token`, `cloudflare_zone_id`, `cf_verify_secret`, `ecs_task_*`, `ai_agent_*`, `staging_active`, `min_capacity`, `max_capacity`. |
| `terraform.tfvars.example` | Example file. **Don't use directly** — the actual envs in `envs/*.tfvars` differ in shape. References a phantom `worker_script_content` var that no longer exists. |
| `backend.tf` | S3 backend config. Bucket `arcadebox-prod-terraform-state` (sic), key `arcadesbox/test/terraform.tfstate`, DynamoDB lock table `arcadesbox-prod-terraform-locks`, region `us-east-1`. The `test/` in the key is a vestige from before workspaces; with workspaces enabled, the actual state lives at `env:/<workspace>/arcadesbox/test/terraform.tfstate`. |
| `providers.tf` | Required versions: TF ≥ 1.12.0, AWS ~> 6.0, time ~> 0.13, Cloudflare ~> 5.13. Four AWS providers: default region (var), `us-east-1` alias (unused but kept for ACM if ever needed), `r2` alias (S3-compatible to Cloudflare R2), `ses_region_provider` alias. Cloudflare provider authenticates via `var.cloudflare_api_token`. |
| `locals.tf` | Two locals: a placeholder Worker script (deployed once on first apply, then ignored), and `enable_ecs_exec` (true for non-prod). |
| `variables.tf` | All input variables. The "AI Agent Service" block at the bottom is **uncommitted in-flight**. |
| `outputs.tf` | Outputs for SES (DKIM CNAMEs etc.), Cloudflare Worker/KV/queue, AI agent (uncommitted), Redis. The role ARN outputs live in `iam_github.tf` and `iam_github_terraform.tf` instead of here. |
| `main.tf` | **Empty file**. Kept to satisfy editors / Terraform expectations. Safe to leave. |
| `locking.tf` | A DynamoDB job-lock table (`*-job-locks-*`) used by the backup tool, not by Terraform itself. Confusing name; this is **not** the TF state lock table. |
| `networking.tf` | VPC, subnets, IGW, NAT GW (prod-only via `count`), route tables, ALB SG (`80/443` in), ECS SG (`5000` from ALB only). |
| `networking_s3_endpoint.tf` | S3 gateway endpoint attached to private route table — saves NAT GW egress fees on S3 calls in prod. |
| `alb.tf` | App ALB, target group, HTTP→HTTPS redirect, HTTPS listener. Health check `GET /api/health`, 30s interval. ACM cert wired in via `aws_acm_certificate_validation`. |
| `acm.tf` | ACM cert for API domain, DNS validation records in Cloudflare, 60s `time_sleep` for replication before listener uses cert. |
| `dns.tf` | Cloudflare DNS records. Root `@`, SPF, and 5× SendGrid CNAMEs are **prod-only** (`count`). API CNAME and frontend CNAME exist in all envs. SendGrid records have hardcoded names like `57531807` — these are the customer-specific values from SendGrid's sender-auth setup. |
| `ecs.tf` | ECS cluster, capacity providers, app log group, app task def, app service. Task CPU/memory drop to `256/512` in dev regardless of var. Desired count: prod=5, dev=1, staging=`staging_active ? 5 : 0`. **`service_connect_configuration` block on the service is uncommitted** (added for AI agent). |
| `ecs_autoscaling.tf` | Three target-tracking policies (CPU 60%, memory 60%, ALB RPS 1000). Skipped in development. Min/max capacity from vars. |
| `ecs_backup.tf` | Backup tool task: dedicated IAM role, log group, task def. Uses `backup_tool` ECR. Image at `:latest`. Wired to scheduler. |
| `scheduler.tf` | EventBridge `schedule_group`, IAM role `eventbridge_scheduler_ecs_role`, daily `cron(0 2 * * ? *)` schedule that runs the backup-tool task. |
| `ecr.tf` | Two ECR repos: `chareli-server` and `backup-tool`. Mutable tags, scan-on-push. AI agent ECR is in `ecr_ai_agent.tf`. |
| `s3.tf` | AWS backup bucket (versioned, encrypted, Glacier-IR after 30d, expire old versions after 365d), S3 replication role/policy, replication to archive bucket, ALB access logs bucket (encrypted, 30d expire, ELB account write policy). |
| `s3_archive.tf` | Immutable archive bucket with **Object Lock COMPLIANCE mode (90-day retention)**. Lifecycle to Deep Archive after 30d. **Cannot be deleted by anyone, including root, until the lock period expires.** Be careful. |
| `elasticache.tf` | Redis (replication group, subnet group, custom parameter group with `noeviction`, dedicated SG). Provisioned only when `enable_redis = true`. Single node in dev/staging, 2 nodes in prod with auto-failover. Uses cache.t4g.micro in dev, cache.t4g.small elsewhere. |
| `ses.tf` | SES domain identity + DKIM + email identity for sender. Cloudflare DNS records (TXT + 3× CNAME) for DKIM. |
| `secrets.tf` | Two `aws_secretsmanager_secret` shells: `application-secrets` and `backup-tool-secrets`. **Values are not in Terraform.** They're populated by `scripts/upload-secrets.sh`. |
| `scripts/upload-secrets.sh` | Bash script that converts a `.env` file to JSON via jq and creates/updates the corresponding AWS Secrets Manager secret. Args: env-file, secret-name, region. Has a `DRY_RUN=true` mode. |
| `iam_ecs.tf` | ECS task execution role + task role. Execution role has the AWS-managed `AmazonECSTaskExecutionRolePolicy` plus a custom secrets-read policy for both Secrets Manager shells. Task role has SES send + Secrets Manager read (the latter is vestigial since the app no longer fetches secrets at runtime). ECS Exec / SSM is attached when `enable_ecs_exec = true`. |
| `iam_github.tf` | App-deploy OIDC role for `chareli` repo. Permissions are tightly scoped: ECR push to two repos (chareli-server + ai-agent), ECS register/update on two services + two task families, IAM PassRole to four task roles (gated to `ecs-tasks.amazonaws.com`). Output: `github_actions_role_arn`. |
| `iam_github_terraform.tf` | Terraform-CI OIDC role for **this** repo. **AdministratorAccess** attached. Trust gated to `repo:${var.github_org}/iac-arcadesbox:*`. Output: `github_terraform_ci_role_arn`. |
| `iam_local_dev_user.tf` | Optional IAM user (`create_local_dev_user`) for local development. Read-only Secrets Manager + SES send. Outputs the secret access key — **store it once at creation; rotation requires destroy/create**. |
| `r2.tf` | Two R2 buckets via S3-compat alias provider: `*-games-cdn-*` (CORS configured per env), `*-r2-backup-*`. R2 → game-zip-queue event notification on `temp-games/*.zip` PutObject. |
| `worker.tf` | Single Worker shell with bindings (R2 bucket, KV namespace, two queues, plain-text and secret-text envs). `keep_bindings` set so wrangler-side deploys don't drop bindings. `lifecycle.ignore_changes = [content]` so Terraform never overwrites code that wrangler deployed. Observability enabled with 10% sampling. |
| `kv.tf` | One Workers KV namespace `game_status` for worker-side status tracking. |
| `queues.tf` | Two queues (`game_zip_queue`, `game_zip_dlq`). Comment at top warns against managing `cloudflare_queue_consumer` here — wrangler owns it. |
| `dashboard.tf` | Composes a CloudWatch dashboard from three widget locals: standard (ALB + ECS), redis (conditional), logs (CloudWatch Logs Insights query against the app log group). |
| `alarms.tf` | SNS topic + 4 standard alarms (ALB 5xx, ALB latency, ECS CPU, ECS memory) + Redis alarms generated from a `for_each` over expected node IDs. **AI agent CPU/memory alarms are uncommitted.** |
| `waf.tf` | WAFv2 web ACL with default-block + allow-on-`x-origin-verify`-header rule. **Production only.** |
| `wrangler.toml` | Top-level wrangler config — used for `npm run build:gatekeeper` only (the dist/ folder). Note this is for the *gatekeeper* worker; the *zip-processor* worker is provisioned by Terraform but its actual code lives in `chareli` repo. |
| `package.json` | Wrangler dependencies for the gatekeeper worker. Build via `npm run build:gatekeeper`. |
| `workers/game_gatekeeper.js` | Source for the JWT-verifying R2 gateway worker (only fetches files; signed cookies expected from main backend). |
| `dist/game_gatekeeper.js` | Built worker output. **In `.gitignore` but exists on disk** — wrangler-built artifact. Don't edit. |
| `envs/dev.tfvars` `staging.tfvars` `prod.tfvars` `testing.tfvars` | **Gitignored env-specific tfvars.** Currently contain hardcoded R2 keys, JWT secrets, webhook secrets, and (in staging/prod) Cloudflare API tokens. See [§7](#7-secrets-tfvars-and-configuration). |
| `.env*` (root) | Several `.env.{ai,dev,staging,prod,test,backup,backup.*,example}` files. These are **not** consumed by Terraform; they exist to feed `scripts/upload-secrets.sh` when populating Secrets Manager values. They are gitignored. |
| `.terraform.lock.hcl` | **Gitignored.** Provider versions are not pinned in git, so CI and local installs may drift within `~> 6.0` etc. constraints. See [§11](#11-landmines-surprises-and-gotchas). |
| `.history/` | VS Code "Local History" extension auto-snapshots. ~250 files. Gitignored. Cosmetic only. |
| `node_modules/`, `.wrangler/`, `dist/` | Wrangler/Node tooling artifacts. Gitignored. |

---

## 4. Environments and the workspace model

Three environments are wired through CI:

| Branch | Workspace | tfvars file | Region | Domain |
|---|---|---|---|---|
| `dev` | `development` | `envs/dev.tfvars` | `eu-central-1` | `*.dev.arcadesbox.com` (api at `api-dev.arcadesbox.com`) |
| `staging` | `staging` | `envs/staging.tfvars` | `eu-central-1` | `*.staging.arcadesbox.com` |
| `main` | `production` | `envs/prod.tfvars` | `us-east-1` | `arcadesbox.com` (api at `api.arcadesbox.com`) |

A fourth file, `envs/testing.tfvars`, exists for `environment = "test"` but **no branch maps to it** in the workflow. It's used (or was used) for ad-hoc local applies; safe to leave in place but consider deleting if no one's actually applying it.

**Branch → workspace selection happens in CI** (`.github/workflows/terraform.yml:30-54`). The `setup` job parses `github.base_ref` (PR) or `github.ref_name` (push) to pick the workspace and tfvars path. Push to `main` ⇒ production; push to `staging` ⇒ staging; push to `dev` ⇒ development. Pushes to any other branch (e.g., `cloudflare-dns`) **fail the workflow** at the setup step.

**Local applies must select the workspace explicitly:**

```bash
terraform workspace select development   # or staging / production
terraform plan -var-file=envs/dev.tfvars
```

There is no `default` workspace pinned to any environment. If you run `terraform plan` without selecting a workspace, you'll be operating against the `default` workspace's state, which is empty. Don't apply blindly.

**Resource naming uses three components:**
- `var.app_name_prefix` (`arcadesbox` everywhere)
- `var.environment` (`development` / `staging` / `production` / `test`)
- `var.infra_suffix` (`v1` everywhere)

Bumping `infra_suffix` from `v1` → `v2` recreates **every named resource** — useful for blue-green destroy-and-recreate, terrible if done by accident. There's no current automation around this.

---

## 5. State, locking, and the backend

`backend.tf`:

```hcl
terraform {
  backend "s3" {
    encrypt        = true
    bucket         = "arcadebox-prod-terraform-state"   # NB: single 'r', not "arcades..."
    key            = "arcadesbox/test/terraform.tfstate"  # vestigial; workspace prefix wins
    region         = "us-east-1"
    dynamodb_table = "arcadesbox-prod-terraform-locks"
  }
}
```

With workspaces enabled, the actual state objects live at:

```
s3://arcadebox-prod-terraform-state/env:/development/arcadesbox/test/terraform.tfstate
s3://arcadebox-prod-terraform-state/env:/staging/arcadesbox/test/terraform.tfstate
s3://arcadebox-prod-terraform-state/env:/production/arcadesbox/test/terraform.tfstate
```

The `arcadesbox/test/` segment is misleading but functionally inert — every workspace gets its own state object via the `env:/<workspace>/` prefix S3 backend uses. **Don't "fix" the key path** without first migrating state; you'll orphan all three states.

DynamoDB locking is via `arcadesbox-prod-terraform-locks` (PAY_PER_REQUEST). A failed apply can leave a stale lock; if you see `Error acquiring the state lock` and you know no apply is running, force-unlock with the LockID from the error message. Don't make a habit of this.

**Bootstrap chicken-and-egg:** the S3 bucket and DynamoDB table must exist *before* `terraform init`. They are not managed by this Terraform — they were created out of band. If they're ever destroyed, this repo cannot bootstrap itself; you'll need to recreate them manually (or temporarily switch to a local backend, init, create them, then `terraform init -migrate-state`).

---

## 6. CI/CD pipeline (`.github/workflows/terraform.yml`)

Three jobs:

1. **`setup`** — parses the branch, emits `environment` / `workspace` / `tfvars` outputs.
2. **`terraform-plan`** — runs on every push and PR. Init, validate, plan, upload artifact, sticky-comment plan output on PRs.
3. **`terraform-apply`** — runs on `push` only (never on PR). Downloads the plan artifact and applies it. Gated by GitHub Environment protection rules.

### Triggers

```yaml
on:
  push:
    branches: [ dev, staging, main ]
  pull_request:
    branches: [ dev, staging, main ]
  workflow_dispatch:
```

PRs targeting any of those three branches run a plan. Pushes (i.e., merges) run plan + apply.

### Required GitHub repo secrets

The workflow expects these to be configured in GitHub at **Settings → Secrets and variables → Actions**:

| Secret name | What it is | How to get it |
|---|---|---|
| `AWS_TERRAFORM_ROLE_ARN` | Output of `terraform output github_terraform_ci_role_arn` (the AdministratorAccess role) | After first apply that creates the role |
| `AWS_REGION` | Region for OIDC role assumption (typically `us-east-1`, since the IAM role is global anyway) | Static |
| `TF_VAR_R2_SECRET_ACCESS_KEY` | R2 secret access key | Cloudflare → R2 → API tokens |
| `TF_VAR_R2_ACCESS_KEY_ID` | R2 access key id | Cloudflare → R2 → API tokens |
| `TF_VAR_WORKER_JWT_SECRET` | JWT shared secret used by the gatekeeper worker and the backend | Generated |
| `TF_VAR_CLOUDFLARE_API_TOKEN` | Cloudflare API token (Workers + KV + Queues + DNS scopes) | Cloudflare → My Profile → API tokens |
| `TF_VAR_CLOUDFLARE_ZONE_ID` | Zone ID for `arcadesbox.com` | Cloudflare dashboard, overview pane |

### GitHub Environments

The workflow uses GitHub Environments named `development`, `staging`, `production`. **You must create these in the repo settings.** I have reasonable confidence they exist (since CI was presumably tested), but I haven't verified what protection rules are configured on `production`. The README claims production requires manual approval — **verify this in `Settings → Environments → production` before relying on it**. Add at least one required reviewer if absent.

### Known issues with the workflow

> ⚠️ The workflow was added in commit `2cc6c91` on 2026-04-30 and **may not have been run end-to-end successfully**. Treat it as a draft until first green run.

1. **Action versions in the apply job don't exist** (as of writing):
   - `actions/checkout@v6` — current is `v4`
   - `aws-actions/configure-aws-credentials@v6` — current is `v4`
   - `actions/download-artifact@v8` — current is `v4`
   - `hashicorp/setup-terraform@v4` — current is `v3`

   The plan job correctly uses `@v4`, `@v4`, `@v4`, `@v3`. **Fix the apply job to match the plan job's versions** before relying on apply.

2. **`tfvars` files are referenced but gitignored.** The plan command includes `-var-file=${{ needs.setup.outputs.tfvars }}` (line 101), but `envs/*.tfvars` are not in the repo. The workflow has no step that fetches them. Variables that the workflow injects via `TF_VAR_*` env (lines 67-71, 144-148) cover only:
   - `r2_secret_access_key`, `r2_access_key_id`, `worker_jwt_secret`, `cloudflare_api_token`, `cloudflare_zone_id`

   Variables that **only** appear in tfvars and have no `TF_VAR_*` injection in CI:
   - `webhook_secret` (sensitive, no default)
   - `cf_verify_secret` (sensitive, has default `""`)
   - `cloudflare_account_id`, `r2_account_id`, `cloudflare_pages_cname_target`, `cloudflare_workers_subdomain`, `r2_public_cname_target`
   - `github_org`, `github_repo`, `github_branch`
   - `frontend_domain_name`, `api_domain_name`, `games_cdn_domain_name`
   - `root_domain_name`, `ses_sending_domain`, `ses_from_email_address`
   - `aws_region`, `ses_region`, `environment`, `infra_suffix`
   - `enable_redis`, `staging_active`, `min_capacity`, `max_capacity`, `ecs_task_cpu`, `ecs_task_memory`
   - `ai_agent_*` (uncommitted block)

   **Without a tfvars file on the runner, `terraform plan` will fail** prompting for `webhook_secret` (since it's marked `sensitive` with no default). Plan will also produce wrong values for env-specific config like `aws_region` and domains.

   Choose one of these remediation paths (see [§13](#13-recommended-first-week-plan)):

   **(a) Move all values to GitHub secrets/variables.** Add a `TF_VAR_*` env entry in the workflow for every var. Pros: no file shuffling. Cons: tedious.

   **(b) Store tfvars in S3 and fetch in CI.** Add a step before `terraform init` that does `aws s3 cp s3://.../envs/dev.tfvars envs/dev.tfvars`. Pros: small diff. Cons: yet another secret-bearing place to keep clean.

   **(c) Encrypt tfvars in-tree with SOPS or git-crypt.** Industry standard. Pros: tfvars become committable. Cons: requires KMS keys, contributor onboarding.

   I'd pick (c) for long-term, (b) as a stopgap.

3. **`workflow_dispatch` does not pass an environment input.** Manual runs use `github.ref_name` to pick the environment, so a manual dispatch from the wrong branch will target the wrong env. Consider adding a workflow_dispatch input that lets the operator override.

4. **PR plan posts the entire plan as a sticky comment.** If a plan exceeds GitHub's comment size limit (~65k chars), the action will truncate or fail. Consider pruning with a `terraform show -json | jq` summary if this becomes an issue.

5. **No drift detection.** The workflow only acts on push/PR. Consider adding a daily `workflow_schedule` job that runs `terraform plan -detailed-exitcode` on each environment and notifies on drift.

### Two GitHub OIDC roles, don't confuse them

| Role | Trust scope | Purpose | Permissions |
|---|---|---|---|
| `arcadesbox-${env}-${suffix}-github-oidc-role` (in `iam_github.tf`) | `repo:${var.github_org}/${var.github_repo}:*` (the **chareli** app repo) | App deploys (push to ECR, update ECS service) | Tightly scoped: ECR + ECS + PassRole gated to `ecs-tasks.amazonaws.com` |
| `arcadesbox-${env}-${suffix}-terraform-ci-role` (in `iam_github_terraform.tf`) | `repo:${var.github_org}/iac-arcadesbox:*` (this repo) | Terraform plan/apply | `AdministratorAccess` |

Both roles trust the **GitHub OIDC provider** (`token.actions.githubusercontent.com`), which is referenced as a **data source** (`data "aws_iam_openid_connect_provider" "github"` at the top of `iam_github.tf`). That means **the OIDC provider must already exist in the AWS account** — it's not provisioned here. If you ever rebuild the AWS account from scratch, create it first via:

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

(The thumbprint is GitHub's. AWS auto-rotates these now, but providing one on creation is still required.)

---

## 7. Secrets, tfvars, and configuration

There are **three distinct secret-bearing surfaces** in this repo. Knowing which one a value lives in is critical.

### (1) Terraform inputs — `envs/*.tfvars` files

**Location:** `envs/{dev,staging,prod,testing}.tfvars`
**Tracked in git?** No (`.gitignore` line 23 globs `*.tfvars`).
**Currently contain:**
- Hardcoded R2 access key id + secret access key
- Hardcoded worker JWT secret (per env)
- Hardcoded webhook_secret (staging + prod, identical value — should be unique per env)
- Hardcoded Cloudflare API token (staging, prod)
- Hardcoded `cf_verify_secret` (prod)
- Plus all non-sensitive config: domains, region, account id, GitHub org/repo, autoscaling sizes, AI agent flags

**Risk:** these files exist in plain text on every contributor's machine and were probably exchanged via Slack/email at some point. Treat all current values as compromised once handoff completes.

**What to do (recommended on day 1 of new engineer's tenure):**
1. Rotate every secret currently in these files (R2 keys, Cloudflare API token, worker JWT, webhook_secret, cf_verify_secret).
2. Re-issue the rotated values via a secret store (Vault, AWS Parameter Store, or 1Password Connect).
3. Implement remediation path (a), (b), or (c) from [§6](#6-cicd-pipeline-githubworkflowsterraformyml) so CI no longer needs the files on disk.
4. Update Secrets Manager values that depend on these (e.g., `WORKER_JWT_SECRET` in `application-secrets`).
5. Notify chareli backend team — anything they have hardcoded must rotate too.

### (2) Application runtime config — AWS Secrets Manager

**Location:** Two AWS Secrets Manager secrets, one per environment:
- `arcadesbox/${environment}/${infra_suffix}/application-secrets`
- `arcadesbox/${environment}/${infra_suffix}/backup-tool-secrets`

**Tracked in git?** Only the **shells** (name + ARN) are in `secrets.tf`. **Values are populated manually** — Terraform doesn't manage them. This is intentional (so secret rotation doesn't trigger Terraform diffs). The header comment in `secrets.tf:12-14` states this.

**How values get there:** Run `scripts/upload-secrets.sh`:

```bash
# Convert local .env.staging to JSON and upload to the staging app secret in eu-central-1
bash scripts/upload-secrets.sh \
  .env.staging \
  arcadesbox/staging/v1/application-secrets \
  eu-central-1

# Dry-run first if you want to preview
DRY_RUN=true bash scripts/upload-secrets.sh .env.staging arcadesbox/staging/v1/application-secrets eu-central-1
```

The script handles bash-style env file quoting (single, double, unquoted, `\n`/`\t` escapes) and either creates or updates the secret. It does **not** delete keys that disappear from the .env file — orphaned keys persist until you manually clean them up via the AWS console or CLI.

**.env files that feed this:**
- `.env.example` — reference template
- `.env.dev`, `.env.staging`, `.env.prod`, `.env.test` — env-specific values
- `.env.ai` — for the AI agent secrets (in-flight)
- `.env.backup.{dev,staging,prod,test}` — for the backup-tool secrets
- Symlinks `.env` → `.env.staging`, `.env.backup` → `.env.backup.staging` (current local default)

All of these are gitignored. They live on the operator's machine and contain real secrets. Same risk as tfvars — treat as compromised on handoff.

**Keys consumed by the main app task definition** (`ecs.tf:73-137`): DB_*, NODE_ENV, PORT, STORAGE_PROVIDER, JWT_*, WORKER_JWT_SECRET, OTP_EXPIRY_MINUTES, INVITATION_EXPIRY_DAYS, AWS_SIGNED_URL_EXPIRATION, SUPERADMIN_*, EMAIL_*, SES_FROM_EMAIL, SENDGRID_*, RESEND_*, USE_TWILIO, TWILIO_*, CLOUDFLARE_*, R2_*, JSON_CDN_*, ZIP_PROCESSING_MODE, LOAD_TEST_BYPASS_TOKEN, CLOUDFLARE_API_TOKEN, CLOUDFLARE_CDN_ZONE_ID, CLOUDFLARE_KV_NAMESPACE_ID, CLOUDFLARE_WEBHOOK_SECRET. **The list of keys must match what the app expects** — see chareli backend's config loader for the source of truth.

**Keys consumed by the backup-tool task** (`ecs_backup.tf:101-108`): R2_SOURCE_*, R2_DEST_*.

**AI agent keys (in-flight)** are listed in `secrets_ai_agent.tf:7-19`.

### (3) GitHub Actions secrets

Listed in [§6](#6-cicd-pipeline-githubworkflowsterraformyml). These exist outside this repo entirely.

### Bootstrap secret-flow on a fresh environment

When you spin up a new env (or a new `infra_suffix` for blue/green), the order matters:

1. `terraform apply` (creates the Secrets Manager **shells**, ECS service, etc.). The ECS service will **fail to start tasks** because the secrets shells exist but have no values yet — task creation succeeds, but the container fails on missing keys.
2. `bash scripts/upload-secrets.sh .env.<env> arcadesbox/<env>/v1/application-secrets <region>` populates the shell.
3. Re-deploy the ECS service or wait for the next attempted restart. ECS will fetch values on the next task start.

For the backup-tool secret, replace `application-secrets` with `backup-tool-secrets` and use `.env.backup.<env>`.

For the AI agent (when in-flight work lands), it'll be `arcadesbox/<env>/v1/ai-agent-secrets` and `.env.ai`.

---

## 8. IAM roles and trust relationships

A non-exhaustive map of who can do what. Use it when an `AccessDenied` error confuses you.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  GitHub OIDC Provider (token.actions.githubusercontent.com)              │
│  └─ data source — must exist in AWS account before this Terraform runs   │
└─────┬──────────────────────────────────────────────────┬─────────────────┘
      │ trust: repo:Really-Great-Tech/iac-arcadesbox:*   │ trust: repo:IP-Quantum-Ltd/chareli:*
      ▼                                                  ▼
┌────────────────────────────┐                  ┌────────────────────────────┐
│ github_terraform_ci_role   │                  │ github_oidc_role           │
│ (this repo's CI)           │                  │ (chareli backend's CI)     │
│ AdministratorAccess         │                  │ ECR push, ECS deploy,      │
└────────────────────────────┘                  │ PassRole→ecs_task_*        │
                                                └────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│  ECS Service Principal (ecs-tasks.amazonaws.com)                         │
└─────┬──────────────────────────────────────────────────┬─────────────────┘
      ▼                                                  ▼
┌────────────────────────────┐                  ┌────────────────────────────┐
│ ecs_task_execution         │ pulls image,     │ ecs_task                   │
│ - ECR pull (managed)       │ fetches secrets  │ - SES SendEmail            │
│ - Secrets Manager Get      │                  │ - Secrets Manager Get      │
│   (application + backup)   │                  │   (vestigial; app uses     │
│ - SSM (if non-prod)        │                  │   container `secrets` block)│
└────────────────────────────┘                  │ - SSM (if non-prod)        │
                                                └────────────────────────────┘

┌────────────────────────────┐                  ┌────────────────────────────┐
│ ecs_backup_task             │                  │ eventbridge_scheduler_     │
│ - SecretsManager Get       │                  │ ecs_role                   │
│   (backup-tool secret)     │                  │ - ecs:RunTask (backup tool) │
│ - S3 backup bucket R/W     │                  │ - PassRole → backup task    │
│ - DynamoDB job-locks       │                  └────────────────────────────┘
└────────────────────────────┘

┌──────────────────────────────────────────────────────────────────────────┐
│ s3_replication_role (Service principal: s3.amazonaws.com)                │
│ - Read source bucket (aws_backup_bucket)                                 │
│ - Write to destination (archive_bucket)                                  │
└──────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────┐  (uncommitted, AI agent)
│ ai_agent_task_execution    │
│ - ECR pull (managed)       │
│ - SecretsManager Get       │
│   (ai-agent-secrets)       │
└────────────────────────────┘
┌────────────────────────────┐
│ ai_agent_task               │
│ - SSM (non-prod)            │
│ - No inline policy          │
│   (talks to external HTTPS  │
│    only)                    │
└────────────────────────────┘
```

**Local IAM user (`iam_local_dev_user.tf`)** is a separate beast: created when `create_local_dev_user = true` (currently `false` in all envs). If you ever turn it on, the Terraform output exposes the secret access key **once**; lose it and you have to destroy/recreate the access key.

---

## 9. In-flight work on `cloudflare-dns` branch

This branch (the one you're on as I write this) has uncommitted work in two states. **It is one logical change** — the goal was to add an internal "AI agent" ECS service that talks to the main backend over Service Connect.

### Untracked new files (6)

```
ecr_ai_agent.tf       # ECR repo + lifecycle policy for ai-agent images
ecs_ai_agent.tf       # Log group, task def, ECS service. Service Connect enabled,
                      # service registers as 'ai-agent' on port 8000.
iam_ai_agent.tf       # Execution role + task role (no inline policy).
secrets_ai_agent.tf   # Secrets Manager shell `arcadesbox/<env>/v1/ai-agent-secrets`.
sg_ai_agent.tf        # SG: ingress 8000 only from main backend's SG, egress all.
service_discovery.tf  # Cloud Map HTTP namespace `arcadesbox-<env>.local` for
                      # Service Connect.
```

### Tracked files modified (5)

```
alarms.tf       # +2 alarms (ai_agent CPU, memory) — see git diff alarms.tf
ecs.tf          # +service_connect_configuration block on the main app service so
                # it can resolve `http://ai-agent:8000` via Cloud Map.
iam_github.tf   # +ECR repo arn for ai-agent in ECRPushAccess
                # +task definition family for ai-agent in ECSDeployAccess
                # +ai_agent service id in ECSDeployAccess
                # +ai_agent_task_execution + ai_agent_task arns in PassRole
outputs.tf      # +4 outputs (log group name, service name, task family, sg id)
variables.tf    # +ai_agent_cpu, ai_agent_memory, ai_agent_image_tag, ai_agent_active
```

The **tracked files reference resources defined in the untracked files** (e.g., `aws_ecs_service.ai_agent`, `aws_iam_role.ai_agent_task`, `aws_service_discovery_http_namespace.main`). If you `git stash` the modified files but leave the untracked ones in place, validation will pass. If you `git stash -u` (including untracked) but leave the modified ones, validation **breaks** because the modified files reference now-missing resources.

**This change is atomic.** Either land it in one commit/PR, or back it out fully.

### Status of the change

- All envs/*.tfvars have `ai_agent_active = false`. Even after a successful apply, `desired_count` is 0 and no tasks run — no ongoing AWS spend.
- All envs have `ai_agent_image_tag = "placeholder"`. The image doesn't exist in ECR yet. To activate, the AI team needs to push a real image to `arcadesbox-ai-agent-<env>-v1` and the operator needs to flip `ai_agent_active = true` and update `ai_agent_image_tag`.
- Service Connect requires a Cloud Map HTTP namespace, which `service_discovery.tf` creates. **Adding Service Connect to the main app service is a service replacement** in some Terraform/AWS provider versions — verify with `terraform plan` and review carefully before applying. The main app's `lifecycle.ignore_changes` does NOT include `service_connect_configuration`, so this **will** show in the plan diff.
- Comment at `ecs_ai_agent.tf:113-115` notes that `desired_count` is intentionally pinned at 1 (or 0) because the agent's in-memory job queue doesn't tolerate multiple workers. Phase VI 6.1 of the AI team's progress tracker (in chareli repo) describes a future Redis-backed queue.

### Recommended next steps for this branch

1. Check whether the AI team has pushed an image to ECR. If not, leave `ai_agent_active = false` and apply only the infra so the resources exist.
2. **Be aware that adding Service Connect to the main app service may cause a brief downtime** when the service replaces. Double-check by running plan in `development` first.
3. Open a PR from `cloudflare-dns` → `dev` to test the change in development. Don't push directly to `main`.
4. Coordinate with the AI team on cutover; verify connectivity from the main backend via `aws ecs execute-command` after apply.

---

## 10. Known problems with the existing README

The `README.md` is the project's onboarding doc, but parts of it have decayed since the project moved DNS to Cloudflare and the GitHub repo moved to `Really-Great-Tech`.

| Section | Issue |
|---|---|
| Architecture diagram | Says "Route 53 DNS"; actual DNS is on Cloudflare (commit `2c21928`). The diagram is wrong but not misleading enough to fix during handoff. |
| "Repository Structure" tree | Doesn't list `iam_github_terraform.tf`, `kv.tf`, `queues.tf`, `service_discovery.tf`, `sg_ai_agent.tf`, `ecr_ai_agent.tf`, `ecs_ai_agent.tf`, `iam_ai_agent.tf`, `secrets_ai_agent.tf`, `s3_archive.tf`, `dashboard.tf`, `scheduler.tf`, `locking.tf`, `networking_s3_endpoint.tf`. |
| "Backend repo URL" | Says `https://github.com/Really-Great-Tech/chareli`; **the real backend is at `https://github.com/IP-Quantum-Ltd/chareli`** (per `envs/*.tfvars` `github_org = "IP-Quantum-Ltd"`). |
| Frontend repo URL | Same broken link. |
| `terraform.tfvars.example` | The example has a `worker_script_content` variable that no longer exists (worker code is wrangler-deployed now). Also missing `webhook_secret`, `ecs_task_*`, AI agent vars, autoscaling vars, `cf_verify_secret`. |
| "`terraform plan`" / "`terraform apply`" snippets | Don't mention `terraform workspace select <env>` or `-var-file=envs/<env>.tfvars`, both of which are required. |
| GitHub OIDC section | Shows only `terraform output github_actions_role_arn`; doesn't mention the second role (`github_terraform_ci_role_arn`) which is the one the IaC pipeline uses. |
| Maintainers | Lists `christian@reallygreattech.com`, but I'm departing 2026-05-08. Update to whoever's taking over. |

I have not edited the README in this handoff PR. The next engineer should rewrite it (or replace it with a pointer to this HANDOFF.md and the runbook).

---

## 11. Landmines, surprises, and gotchas

- **`infra_suffix = "v1"`** — bumping this re-creates every resource. There's no automation around this; it's a manual blue/green knob.
- **WAF only in production.** Non-prod ALBs are public. If you add bot-management or other security controls, decide whether they should also apply to non-prod.
- **NAT Gateway only in production.** Non-prod ECS tasks run in **public** subnets with **public IPs** assigned (`assign_public_ip = true`). They egress directly via the IGW. This saves ~$45/mo per non-prod env but means tasks have publicly routable IPs (their SG only allows ingress from the ALB SG, so this is fine, but it surprises people).
- **Service Connect in development uses public subnets too**, since development tasks run in public subnets. The Cloud Map namespace is HTTP-only (no DNS), so this works, but if you ever switch development to private subnets you'll need to adjust.
- **ECS Exec is on for non-prod, off for prod** (via `local.enable_ecs_exec`). To debug a prod task you have to either flip the local temporarily (and re-deploy task def) or use CloudWatch Logs alone.
- **Worker dual-management.** `worker.tf` has `lifecycle.ignore_changes = [content]` and `keep_bindings`. Terraform owns the shell + bindings; wrangler (from chareli's CI) owns the code. Don't add or remove bindings here without coordinating with the chareli team's `wrangler.toml`. **Adding a binding via wrangler that isn't in this Terraform → your next `terraform apply` will remove it** unless the binding type is in `keep_bindings`.
- **Queue consumer is wrangler-owned.** Don't add `cloudflare_queue_consumer` resources here — wrangler redeployments change the internal `consumer_id`, which would cause perpetual destroy/create drift. The comment in `queues.tf:1-5` is load-bearing.
- **R2 bucket lifecycle is via the `aws.r2` provider alias**, not via Cloudflare's native bucket-lifecycle resource. The aliased provider is just AWS S3 SDK pointed at R2's S3-compatible endpoint. Most S3 features work; some (like Object Lock, replication, encryption-by-default) don't translate. Use Cloudflare's native resources where supported.
- **Glacier IR transition is also applied to non-current versions** (`s3.tf:55-60`). Old versions are not double-transitioned but the lifecycle handles them correctly.
- **Archive bucket has Object Lock COMPLIANCE mode.** Once an object lands there, it cannot be deleted for 90 days, by anyone, including the AWS root account. Test against a fresh bucket if you want to verify policies.
- **ALB access logs bucket has `force_destroy = true`.** A `terraform destroy` will silently nuke logs. Probably fine for the access-log bucket but worth knowing.
- **`aws_acm_certificate_validation` blocks the listener until validation completes.** If Cloudflare DNS is misconfigured (e.g., `proxied = true` on the validation record), validation hangs. The `cloudflare_dns_record.api_cert_validation` correctly sets `proxied = false`.
- **`aws_lb_target_group` health check path is `/api/health`.** If the backend ever moves the health check (or if the prefix changes), update this. There's no easy way to surface a backend-vs-infra contract drift today.
- **`aws_ecs_service.app` has `lifecycle.ignore_changes = [desired_count, task_definition, load_balancer]`**. This is so chareli's CI can deploy new task defs without Terraform rolling them back, and so the autoscaler can change desired_count freely. **First-time provisioning** still needs a real task def to register; subsequent Terraform changes to the task def block won't propagate. To force a task def update through Terraform, use `terraform apply -replace=aws_ecs_task_definition.app`.
- **`cf_verify_secret` is only checked when WAF is enabled (production).** Cloudflare's transform rule must inject the `x-origin-verify` header upstream of the ALB. **There's no Terraform resource managing that transform rule** — it's configured manually in the Cloudflare dashboard. Verify it's still present if WAF starts blocking traffic.
- **`testing.tfvars`** maps to `environment = "test"`. The case statement in CI doesn't handle a `test` branch, so it's only useful for ad-hoc local applies. The `local.enable_ecs_exec` check is `var.environment != "production" && var.environment != "prod"` — `test` triggers exec mode (fine).
- **`.terraform.lock.hcl` is gitignored.** The current locked versions on disk are AWS 6.33.0, Cloudflare 5.17.0, time 0.13.1, null 3.2.4. Without the lock in git, CI will resolve providers fresh each run and could drift. **Consider removing `.terraform.lock.hcl` from `.gitignore`** and committing it. This is a one-line fix that gives you reproducible builds.
- **`pnpm-lock.yaml` is committed.** `package.json` references `wrangler` and `@tsndr/cloudflare-worker-jwt`. The `node_modules` are gitignored. Whoever builds the worker locally will run `pnpm install` (or `npm install`).
- **The "backup-tool" image is at `:latest`** in `ecs_backup.tf`. The build pipeline that pushes this image is **not in this repo and not documented**. Likely lives in chareli or a separate ops repo. Until that's clarified, the daily backup is silently dependent on whoever last pushed `:latest`.
- **EventBridge Scheduler runs in `eu-central-1` for non-prod and `us-east-1` for prod.** A disabled or misconfigured scheduler in a region won't trigger backups; they fail silently unless someone watches the SNS topic or the backup-tool log group.
- **`time_sleep.wait_for_acm_replication`** adds a hardcoded 60s pause after ACM validation. If you ever destroy and recreate the cert, this can extend `terraform apply` by a minute. Removing it can cause the listener to come up before the cert is replicated and serve the wrong cert briefly.
- **Two distinct `chareli` references**: the **app** is "chareli", the **product** is "ArcadesBox". Resource names use `arcadesbox-`; some IAM names use `chareli-` (`local_dev_user_name = "chareli-local-dev-user"`, IAM resource names like `chareli_server`, `chareli_sending_domain`). Don't try to globally rename without a plan.
- **`secrets_ai_agent.tf` lists expected keys in a comment.** That comment IS the spec. If the AI team adds a key, both the comment and the `secrets` block of `ecs_ai_agent.tf:52-103` need updating.

---

## 12. Open questions for the next engineer

These are the things I'd want answers to but never confirmed myself.

1. **Production deployment cadence and approver list.** The README says prod deploys require manual approval via GitHub Environment protection rules. Verify this is configured. If approvers leave the company, it could silently lock out apply.
2. **Where does the backup-tool image build live?** The Terraform consumes `aws_ecr_repository.backup_tool.repository_url:latest`. I never traced the build/push pipeline. Likely in chareli, possibly in a sibling ops repo, possibly someone's laptop.
3. **Database lifecycle.** Postgres + MongoDB credentials end up in `application-secrets`, but neither database is provisioned by this Terraform. RDS? An external managed service? AWS or Atlas? The chareli backend's config is the source of truth. **Find out who owns the database before touching anything that references DB connectivity.**
4. **MongoDB Atlas usage by AI agent.** `secrets_ai_agent.tf` lists MongoDB Atlas keys (`MONGODB_URL`, `MONGODB_VECTOR_INDEX`, etc.). Atlas account ownership and cost ownership unclear.
5. **Cloudflare account access.** The single Cloudflare account `6a174bfe8d474ce652234319a3be34fa` hosts everything. Who else has admin access? Who manages the API token currently in `envs/staging.tfvars`?
6. **SendGrid account.** SendGrid CNAMEs are hardcoded with customer-specific values (`57531807`, `u57531807.wl058.sendgrid.net`). Account owner unknown to me.
7. **Twilio account.** `application-secrets` includes `TWILIO_*`. Owner unknown.
8. **R2 bucket public access.** `r2_bucket_is_public` exists in the README/example but **is not declared as a variable** in `variables.tf`. Either the var was removed or it was renamed. Either way, `r2.tf` doesn't reference it. Probably dead config.
9. **GitHub branch protection on `main`.** Verify `main` requires at least one PR review, that the Terraform CI plan job is a required status check, and that force-pushes are blocked.
10. **ACM cert region.** The cert is in the same region as the ALB (`var.aws_region`). The `us-east-1` provider alias exists in `providers.tf` but isn't used. If you ever swap to CloudFront, you'll need to switch the cert provider to `aws.us-east-1`.
11. **Blue-green / `infra_suffix` handover.** Has `v1` ever been bumped? If you ever need to do this, draft a runbook first — there's no safety net.
12. **Cost monitoring.** No AWS Cost Explorer Anomaly Detection or Cloudflare cost alerts that I can see. Consider adding before the next billing cycle.

---

## 13. Recommended first-week plan

A suggested order of operations if you're picking this up cold.

**Day 1 — Get oriented and unblock yourself**

1. Read this HANDOFF.md end-to-end. ~30–40 min.
2. Get GitHub access to `Really-Great-Tech/iac-arcadesbox` and `IP-Quantum-Ltd/chareli`.
3. Get AWS console access to the account that owns `arcadebox-prod-terraform-state`. (Account ID: derive from `data.aws_caller_identity.current.account_id` after a successful local apply or `aws sts get-caller-identity`.)
4. Get Cloudflare dashboard access to account `6a174bfe8d474ce652234319a3be34fa`.
5. Have Christian (or his backup) hand over the `envs/*.tfvars` files via a secure channel (1Password, Vault, etc.). Store them locally, never commit.
6. Run `terraform init` and `terraform workspace select development` followed by `terraform plan -var-file=envs/dev.tfvars`. Confirm the plan is empty (or is just the in-flight AI-agent diff if you're on `cloudflare-dns`). If not empty, **stop and figure out why** before applying.

**Day 2 — Validate the CI pipeline**

1. Open a no-op PR against `dev` (e.g., a comment-only edit). Watch the `terraform-plan` job run. Confirm it succeeds and posts a sticky plan comment.
2. **Fix the action versions in the apply job** (see [§6](#6-cicd-pipeline-githubworkflowsterraformyml)).
3. Decide on a tfvars-handling remediation (a/b/c) and implement it. Until then, **do not push to `main` or `staging`** — apply will fail with a missing-tfvars error.
4. Verify GitHub Environment protection rules on `production` (require reviewer, restrict to branch `main`).
5. Verify the `AWS_TERRAFORM_ROLE_ARN` and `AWS_REGION` repo secrets exist. Verify all 5 `TF_VAR_*` secrets exist.

**Day 3 — Resolve the in-flight AI agent work**

1. Decide with the AI team and Engineering leadership whether to land the AI agent infra now, defer, or revert.
2. If landing: open a PR from `cloudflare-dns` → `dev`, walk the plan output, apply to dev, smoke test Service Connect from a main backend task (`aws ecs execute-command` then `curl http://ai-agent:8000/health`), then PR to `staging`, then `main`.
3. If deferring: keep `cloudflare-dns` alive (do not delete the branch). Push it to origin so it's not laptop-only.
4. If reverting: discard the modified files and the untracked files together; commit a "revert AI agent" PR if any of the change leaked anywhere. Then notify the AI team.

**Day 4 — Rotate and tighten secrets**

1. Rotate every value currently in `envs/*.tfvars` (R2 keys, Cloudflare API token, JWT secrets, webhook_secret, cf_verify_secret).
2. Update `application-secrets` Secrets Manager values for any keys that depend on rotated values (`WORKER_JWT_SECRET`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_WEBHOOK_SECRET`).
3. Coordinate with chareli backend team on cutover.
4. Move tfvars to a real secret store per [§6](#6-cicd-pipeline-githubworkflowsterraformyml) remediation choice.
5. Commit `.terraform.lock.hcl` if you've decided to pin providers.

**Day 5 — Documentation and handoff close-out**

1. Update `README.md` with the corrections from [§10](#10-known-problems-with-the-existing-readme).
2. Add a real runbook for the operations you'll repeat (or extend `docs/RUNBOOK.md` with anything you discover).
3. Set up cost alerts (AWS Cost Anomaly Detection, Cloudflare billing alerts).
4. Add drift detection to CI (a daily plan job).

---

## 14. External systems and contacts

| System | URL / identifier | Notes |
|---|---|---|
| AWS account | (run `aws sts get-caller-identity`) | Region: `us-east-1` for prod, `eu-central-1` for non-prod |
| Cloudflare account | `6a174bfe8d474ce652234319a3be34fa` | One account hosts DNS, R2, Workers, KV, Queues |
| Cloudflare zone | `9129abffe3ef56e208e66877ec4c62bf` (`arcadesbox.com`) | Same zone for all envs |
| Backend repo | `https://github.com/IP-Quantum-Ltd/chareli` | App code (Express + React). Deploys via OIDC into the app-deploy IAM role |
| This repo | `https://github.com/Really-Great-Tech/iac-arcadesbox` | IaC. Branch `main` → prod, `staging` → staging, `dev` → dev |
| Terraform state bucket | `s3://arcadebox-prod-terraform-state/` (`us-east-1`) | Note typo in name |
| Terraform lock table | `arcadesbox-prod-terraform-locks` (DynamoDB, `us-east-1`) | |
| CloudWatch dashboard | AWS console → CloudWatch → Dashboards → `arcadesbox-dashboard-<env>-v1` | |
| SNS alerts topic | `arcadesbox-alerts-<env>-v1` | Subscribe yourself before Day 1 |
| Sender domains | `dev.arcadesbox.com`, `staging.arcadesbox.com`, `www.arcadesbox.com` | SES-verified, DKIM-CNAMEd via Cloudflare |
| Frontend production URL | `https://www.arcadesbox.com` (Cloudflare Pages) | Pages config not in this repo |
| API production URL | `https://api.arcadesbox.com` (Cloudflare-proxied → ALB) | Cloudflare proxy on, WAF requires `x-origin-verify` header |
| Departing maintainer | Christian Koranteng | korantengchristian@gmail.com — available for handoff questions through 2026-05-08 |
| Sister teams | AI agent team (in chareli repo); Backend team; Frontend team | Identify owners before flipping `ai_agent_active = true` |

---

## Appendix A: One-page architecture cheat-sheet

```
                                                  ┌──────────────────────┐
                                                  │   user's browser     │
                                                  └───────────┬──────────┘
                                                              │
                                  Cloudflare DNS  ◀───────────┘
                                  arcadesbox.com (zone 9129abffe3ef56e208e66877ec4c62bf)
                                              │
        ┌─────────────────────────┬───────────┴───────────┬──────────────────────┐
        │                         │                       │                      │
        ▼                         ▼                       ▼                      ▼
  ┌──────────────┐         ┌──────────────┐         ┌──────────────┐       ┌──────────────┐
  │   (apex)     │         │  www.        │         │  api.        │       │  cdn.        │
  │  proxied to  │         │  CNAME →     │         │  CNAME →     │       │  R2 public   │
  │  192.0.2.1   │         │  Pages       │         │  AWS ALB     │       │  CNAME       │
  │  (redirect)  │         │  (frontend)  │         │  (orange-    │       │              │
  │              │         │              │         │  cloud)      │       │              │
  └──────────────┘         └──────────────┘         └──────┬───────┘       └──────────────┘
                                                            │
                                                            │ HTTPS, x-origin-verify (prod)
                                                            ▼
                                                    ┌───────────────┐
                                                    │  WAFv2 (prod) │
                                                    └───────┬───────┘
                                                            │
                                                            ▼
                                                ┌───────────────────────┐
                                                │  Application LB :443  │
                                                │  ec ALB → :5000 ECS   │
                                                └───────────┬───────────┘
                                                            │
                                                            ▼
                              ┌──────────────────────────────────────────────────────┐
                              │              ECS Fargate cluster                      │
                              │  (FARGATE + FARGATE_SPOT capacity providers)         │
                              │                                                       │
                              │  ┌─────────────┐  Service Connect ┌────────────────┐ │
                              │  │  app svc    │ ◀───────────────▶│ ai-agent svc   │ │
                              │  │  :5000      │  ai-agent:8000   │ :8000 (in-     │ │
                              │  │  (chareli)  │                  │  flight)       │ │
                              │  └─────┬───────┘                  └────────────────┘ │
                              │        │                                              │
                              │        ▼ (R/W)                                        │
                              │  ┌──────────────┐    ┌───────────────┐                │
                              │  │  ElastiCache │    │  Secrets Mgr  │                │
                              │  │  Redis (opt) │    │  app + backup │                │
                              │  └──────────────┘    │  + ai-agent   │                │
                              │                      └───────────────┘                │
                              └──────────────────────────────────────────────────────┘
                                                            │
                              ┌────────────────────┬────────┴─────────┬────────────────┐
                              ▼                    ▼                  ▼                ▼
                       ┌───────────┐         ┌──────────┐      ┌──────────┐    ┌───────────────┐
                       │ ECR       │         │ SES      │      │ S3 logs  │    │ EventBridge   │
                       │ chareli   │         │ DKIM,    │      │ (ALB)    │    │ Scheduler     │
                       │ +backup   │         │ from     │      │ + backup │    │ (daily 02:00) │
                       │ +ai-agent │         │ identity │      │ + archive│    │  → backup-tool│
                       └───────────┘         └──────────┘      │ (Object  │    │     ECS task  │
                                                               │  Lock)   │    └───────────────┘
                                                               └──────────┘

                              ┌────────────────────────────────────────────────┐
                              │              Cloudflare R2                      │
                              │   ┌────────────────┐    ┌──────────────────┐   │
                              │   │  games-cdn-*   │    │  r2-backup-*     │   │
                              │   │  (public CDN,  │    │  (mirror dest    │   │
                              │   │   CORS / event │    │   for backup     │   │
                              │   │   notif on     │    │   tool)          │   │
                              │   │   temp-games/) │    └──────────────────┘   │
                              │   └────────┬───────┘                           │
                              │            │                                    │
                              │            ▼ event                              │
                              │      ┌─────────────────┐                        │
                              │      │ game-zip-queue  │ ──▶ DLQ on retry-fail  │
                              │      └────────┬────────┘                        │
                              │               ▼                                  │
                              │      ┌─────────────────────┐                    │
                              │      │ Cloudflare Worker   │                    │
                              │      │ games-zip-processor │                    │
                              │      │  (code via wrangler │                    │
                              │      │   from chareli;     │                    │
                              │      │   shell + bindings  │                    │
                              │      │   from this repo)   │                    │
                              │      └────────┬────────────┘                    │
                              │               │ webhook (signed)                │
                              └───────────────┼────────────────────────────────┘
                                              │
                                              ▼  https://api.<env>.arcadesbox.com/api/internal/game-processed
                                          (back to ALB)
```

---

## Appendix B: Quick reference of names

For grepping confusion:
- "**chareli**" — internal codename for the application (backend + frontend). Used in IAM names, ECR repo, SES identity vars, and the backend repo name.
- "**ArcadesBox**" — product name. Used in `app_name_prefix = "arcadesbox"` and most resource names.
- "**ip-quantum-ltd**" — GitHub org for the **app** repo.
- "**Really-Great-Tech**" — GitHub org for **this** (IaC) repo.
- "**Really Great Tech**" — the company's commercial name, used in copyright/maintainer footers.

---

*— Christian, 2026-05-07*
