# ArcadesBox Cloud Infrastructure (Terraform + AWS + Cloudflare)

> **Infrastructure-as-Code (IaC)** stack for deploying a secure, scalable cloud environment using **AWS ECS Fargate**, **Cloudflare R2**, and **GitHub Actions OIDC**.

---

## 🌩️ Overview

This repository contains the Terraform configuration for provisioning the **ArcadesBox cloud infrastructure**.
It automates the setup of networking, compute, DNS, secrets management, and security integrations across AWS and Cloudflare.

### What this repository manages

- **AWS ECS Fargate** cluster + Application Load Balancer
- **AWS Secrets Manager** for credentials
- **Cloudflare R2** for game asset storage
- **Cloudflare Worker** for JWT-secured asset delivery
- **AWS SES** for transactional email
- **ElastiCache Redis** (optional caching layer)
- **GitHub Actions OIDC** role for keyless CI/CD
- **Route 53** DNS records and SSL certificates

> 🧩 The **application deployment** (backend and frontend) lives in separate repositories:
>
> - **Backend:** See the [Backend README](https://github.com/Really-Great-Tech/chareli) for build and deployment instructions.
> - **Frontend:** See the [Frontend README](https://github.com/Really-Great-Tech/chareli) (or `/Client` folder) for Cloudflare Pages deployment steps.
>
> This repository **only** manages the underlying infrastructure that supports both.

---

## 🧭 Architecture Diagram

```mermaid
flowchart LR
  subgraph CF[Cloudflare]
    CFU[User Browser]
    CFW[Cloudflare Worker (game_gatekeeper)]
    CFR2[(R2 Storage Bucket)]
    CFP[Cloudflare Pages Frontend]
  end

  subgraph AWS[AWS Cloud]
    R53[Route 53 DNS]
    ALB[Application Load Balancer]
    ECS[ECS Fargate Service]
    SM[AWS Secrets Manager]
    SES[Simple Email Service (SES)]
    REDIS[(ElastiCache Redis)]
  end

  CFU --> CFP
  CFP -->|API Requests| ALB
  ALB --> ECS
  ECS --> SM
  ECS --> SES
  ECS --> REDIS
  CFU -->|Static/Game Assets| CFW
  CFW -->|Verified Request| CFR2
  R53 --> CFU
  R53 --> ALB
```

---

## 📁 Repository Structure

```
├── networking.tf          # VPC, subnets, NAT, and security groups
├── alb.tf                 # Application Load Balancer
├── ecs.tf                 # ECS cluster, tasks, and services
├── ecs_autoscaling.tf     # ECS Service Auto Scaling policies
├── ecs_backup.tf          # AWS Backup plans for ECS/EFS (if applicable)
├── ecr.tf                 # Elastic Container Registry
├── r2.tf                  # Cloudflare R2 configuration
├── worker.tf              # Cloudflare Worker deployment
├── ses.tf                 # SES (email) setup
├── elasticache.tf         # Redis configuration
├── alarms.tf              # CloudWatch Alarms
├── dashboard.tf           # CloudWatch Dashboard
├── iam_*.tf               # IAM roles & policies (ECS, GitHub, Local User)
├── secrets.tf             # Secrets Manager integration
├── terraform.tfvars.example # Example configuration file
├── .env.example           # Example environment file (see below)
├── scripts/
│   └── upload-secrets.sh  # Upload .env → AWS Secrets Manager
├── workers/
│   └── game_gatekeeper.js # Cloudflare Worker logic
├── package.json           # Wrangler dependencies
└── wrangler.toml          # Worker configuration
```

---

## ⚙️ Prerequisites

| Tool                                                                                     | Description                   | Install                   |
| ---------------------------------------------------------------------------------------- | ----------------------------- | ------------------------- |
| [Terraform](https://developer.hashicorp.com/terraform/downloads)                         | Infrastructure as Code engine | `brew install terraform`  |
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | Manage AWS resources          | `brew install awscli`     |
| [Wrangler](https://developers.cloudflare.com/workers/wrangler/get-started/)              | Cloudflare Worker CLI         | `npm install -g wrangler` |
| [jq](https://stedolan.github.io/jq/)                                                     | JSON processor                | `brew install jq`         |

You’ll also need:

- An **AWS account** (permissions: VPC, ECS, ECR, SES, Secrets Manager)
- A **Cloudflare account** with **R2 + Workers** enabled
- A **Route 53** hosted zone for your domain

---

## 🔧 Configuration

### 1. Copy Example Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

### 2. Edit `terraform.tfvars`

Provide your environment-specific values. Below is a comprehensive list of variables you may need to configure:

```hcl
# --- General ---
aws_region            = "us-west-2"
ses_region            = "us-east-1" # SES often requires us-east-1 or specific regions
environment           = "dev"
infra_suffix          = "v1"
app_name_prefix       = "arcadesbox"

# --- Domains ---
root_domain_name      = "example.com"
frontend_domain_name  = "app.dev.example.com"
api_domain_name       = "api.dev.example.com"
games_cdn_domain_name = "games.dev.example.com"

# --- Cloudflare ---
cloudflare_account_id         = "your-cloudflare-account-id"
cloudflare_workers_subdomain  = "youraccount.workers.dev"
cloudflare_pages_cname_target = "pages.dev.example.pages.dev"
r2_account_id                 = "your-cloudflare-account-id"
r2_access_key_id              = "R2ACCESSKEYIDHERE"
r2_secret_access_key          = "R2SECRETACCESSKEYHERE"
r2_public_cname_target        = "public.r2.dev" # Or your custom domain target
r2_bucket_is_public           = true

# --- GitHub Integration ---
github_org    = "Really-Great-Tech"
github_repo   = "iac-arcadesbox"
github_branch = "main"

# --- Email (SES) ---
ses_sending_domain     = "dev.example.com"
ses_from_email_address = "no-reply@dev.example.com"

# --- Application ---
worker_jwt_secret = "super-secret-jwt-key"
image_tag         = "latest"

# --- Optional ---
enable_redis      = false
# redis_node_type = "cache.t4g.micro"
```

> 📘 For a detailed explanation of every variable, see the [**VARIABLES.md**](./VARIABLES.md) document.

---

### 🧱 Terraform State & Providers Configuration

Before deploying, ensure your backend is configured correctly to store state securely.

#### 1. backend.tf

This project uses **S3** for state storage and **DynamoDB** for state locking.

**Production Example (`backend.tf`):**

```hcl
terraform {
  backend "s3" {
    encrypt        = true
    bucket         = "arcadebox-prod-terraform-state"
    key            = "arcadesbox/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "arcadesbox-prod-terraform-locks"
  }
}
```

> ⚠️ **Important:** Ensure the S3 bucket and DynamoDB table exist before initializing, or use a local backend for initial bootstrapping.

#### 2. providers.tf

The provider configuration handles authentication for AWS and Cloudflare.

```hcl
provider "aws" {
  region = var.aws_region
}

provider "cloudflare" {
  # Credentials usually picked up from CLOUDFLARE_API_TOKEN env var
}
```

---

## 🔐 Secrets Management

All secrets are stored securely in **AWS Secrets Manager**.

### 1. Create `.env` file

You can start by copying the provided `.env.example`:

```bash
cp .env.example .env
```

> ⚠️ Refer to the **[Backend Repository README](https://github.com/Really-Great-Tech/chareli/Server)** for a list of all required variables and their purposes.
> This `.env` file will later be uploaded to AWS Secrets Manager for use by ECS.

---

## 🔑 Cloudflare Authentication

Terraform needs to authenticate with Cloudflare to deploy the R2 bucket and Worker.

You’ll need a **Cloudflare API Token** with at least:

- **R2 (Storage):** `Account R2:Edit`
- **Workers:** `Account Workers Scripts:Edit`
- **Zone:** `Zone:Read`

📘 **Official Documentation:**
👉 [Cloudflare Account API Token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)

Once created, export it to your terminal before running Terraform commands:

```bash
export CLOUDFLARE_API_TOKEN="your-cloudflare-api-token"
```

> 💡 Add this line to your shell profile (`~/.bashrc` or `~/.zshrc`) to persist it across sessions.

---

## 🚀 Deploying the Infrastructure

### 1. Initialize Terraform

```bash
terraform init
```

### 2. Plan & Review

```bash
terraform plan
```

### 3. Apply

```bash
terraform apply
```

Terraform provisions:

- AWS networking stack (VPC, subnets, NAT)
- ECS Cluster, ALB, Secrets Manager
- Cloudflare R2, Worker, and DNS records
- SES and IAM roles for GitHub OIDC

---

## 🔄 GitHub Actions OIDC Integration

1. Retrieve IAM role ARN:

   ```bash
   terraform output github_actions_role_arn
   ```

2. Reference it in your GitHub workflow for example:

   ```yaml
   permissions:
     id-token: write
     contents: read

   steps:
     - uses: aws-actions/configure-aws-credentials@v4
       with:
         role-to-assume: <ARN_FROM_OUTPUT>
         aws-region: us-west-2
   ```

---

## ☁️ Cloudflare Configuration

### R2 Bucket

Terraform provisions an R2 bucket and configures CORS for your frontend domain.

### Worker Deployment

`workers/game_gatekeeper.js` validates JWTs and controls asset access.

Deploy manually (if needed):

```bash
npm run build
wrangler deploy
```

Worker bindings:

- `GAMES_BUCKET` — Cloudflare R2 bucket
- `WORKER_JWT_SECRET` — JWT verification key
- `ALLOWED_ORIGINS` — JSON-encoded allowed origins

---

## ⚡ Optional Features

### Enable Redis

```hcl
enable_redis = true
```

Then run:

```bash
terraform apply
```

### SES Email Setup

Check Terraform outputs for DKIM records:

```bash
terraform output ses_dkim_cname_records
```

Add these to Route 53 for email verification.

---

## 📊 Observability

This stack includes a comprehensive "AWS Native" observability suite.

### 🖥️ CloudWatch Dashboard

A unified dashboard is provisioned to monitor system health at a glance.
**Name:** `[app_name]-dashboard-[env]-[suffix]`

**Widgets:**
- **ALB Request Count**: Traffic volume.
- **ALB Latency**: Average target response time.
- **ALB Errors**: 4xx and 5xx error counts.
- **ECS Health**: CPU and Memory utilization.

### 🚨 CloudWatch Alarms

Critical metrics are monitored with alarms that trigger an SNS topic (`[app_name]-alerts-[env]-[suffix]`).

| Alarm | Threshold | Description |
| :--- | :--- | :--- |
| **ALB High 5xx** | > 5 errors / min | Indicates application failures. |
| **ALB High Latency** | > 2s avg latency | Indicates performance degradation. |
| **ECS High CPU** | > 85% | Cluster is under heavy load. |
| **ECS High Memory** | > 85% | Potential memory leak or need for scaling. |

### 🪵 Logs

- **ALB Access Logs**: Enabled and stored in S3 bucket `[app_name]-alb-logs-[env]-[suffix]`. Useful for deep traffic analysis.
- **ECS Application Logs**: Streamed to CloudWatch Logs `/ecs/[app_name]-[env]-[suffix]`.
- **Worker Logs**: Streamed to Cloudflare (if enabled).

---

## 🧹 Teardown

To destroy all resources:

```bash
terraform destroy
```

Confirm with `yes`.

---

## 🛠️ Troubleshooting

| Issue                  | Description                  | Fix                                                 |
| ---------------------- | ---------------------------- | --------------------------------------------------- |
| `AccessDenied`         | IAM policy missing           | Verify AWS permissions                              |
| `InvalidClientTokenId` | Expired session              | Run `aws configure` again                           |
| `InvalidAccessKeyId`   | Wrong Cloudflare credentials | Update `CLOUDFLARE_API_TOKEN` or `terraform.tfvars` |
| `ThrottlingException`  | API rate-limit reached       | Wait and retry                                      |

---

## 📚 References

- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Cloudflare R2](https://developers.cloudflare.com/r2/)
- [Cloudflare Workers](https://developers.cloudflare.com/workers/)
- [Cloudflare Terraform Provider Docs](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)
- [AWS ECS Fargate](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [GitHub OIDC + AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)

---

## 🧾 License

MIT License © 2025 Really Great Tech / ArcadesBox Infrastructure Team

---

## 💬 Maintainers

- **DevOps Lead:** [Christian Koranteng](mailto:christian@reallygreattech.com)
- **Contributors:** Really Great Tech DevOps Team
