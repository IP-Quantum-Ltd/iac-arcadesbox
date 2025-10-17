
---

# ⚙️ Terraform Variables Reference

> This document describes all the variables used in the **Arcadesbox Infrastructure (IaC)** Terraform configuration.

---

## 🏗️ Environment & Naming

| Variable | Type | Example | Description |
|-----------|------|----------|--------------|
| `app_name_prefix` | `string` | `"arcadesbox"` | Prefix applied to all resource names for grouping and identification. |
| `environment` | `string` | `"dev"` | Environment name (e.g., `dev`, `staging`, `prod`). Used in naming and tagging. |
| `infra_suffix` | `string` | `"v1"` | Additional suffix to ensure uniqueness when multiple environments share a domain. |

---

## 🌍 AWS Configuration

| Variable | Type | Example | Description |
|-----------|------|----------|--------------|
| `aws_region` | `string` | `"us-west-2"` | The AWS region where infrastructure will be deployed. |
| `ses_region` | `string` | `"us-west-2"` | Region where SES (email) will be configured. |

---

## 🧩 Domain Configuration

| Variable | Type | Example | Description |
|-----------|------|----------|--------------|
| `root_domain_name` | `string` | `"example.com"` | The root domain managed in Route 53. |
| `frontend_domain_name` | `string` | `"app.dev.example.com"` | Frontend application domain (e.g., Cloudflare Pages). |
| `api_domain_name` | `string` | `"api.dev.example.com"` | Backend API endpoint domain. |
| `games_cdn_domain_name` | `string` | `"games.dev.example.com"` | Domain for serving static or game assets (via Cloudflare Worker). |

---

## ☁️ Cloudflare Configuration

| Variable | Type | Example | Description |
|-----------|------|----------|--------------|
| `cloudflare_pages_cname_target` | `string` | `"pages.dev.example.pages.dev"` | CNAME target for the frontend hosted on Cloudflare Pages. |
| `cloudflare_workers_subdomain` | `string` | `"youraccount.workers.dev"` | Worker subdomain used for default deployment URLs. |
| `r2_account_id` | `string` | `"1234567890abcdef"` | Cloudflare account ID for R2. |
| `r2_access_key_id` | `string` | `"R2ACCESSKEYIDHERE"` | Access key for R2 (used via S3-compatible API). |
| `r2_secret_access_key` | `string` | `"R2SECRETACCESSKEYHERE"` | Secret key for R2 (stored securely). |
| `r2_public_cname_target` | `string` | `"public.r2.examplecdn.com"` | Optional direct CNAME for a public R2 bucket. |
| `r2_bucket_is_public` | `bool` | `true` | If true, skips Worker deployment and serves assets directly, consider setting to false to make bucket private. |

---

## 🧰 GitHub OIDC Configuration

| Variable | Type | Example | Description |
|-----------|------|----------|--------------|
| `github_org` | `string` | `"reallygreattech"` | GitHub organization or user. |
| `github_repo` | `string` | `"arcadesbox-backend"` | Repository name authorized for OIDC access. |
| `github_branch` | `string` | `"main"` | The GitHub branch allowed to assume the OIDC role. |

---

## ✉️ Email (SES) Configuration

| Variable | Type | Example | Description |
|-----------|------|----------|--------------|
| `ses_sending_domain` | `string` | `"dev.example.com"` | Domain used for sending emails via SES. |
| `ses_from_email_address` | `string` | `"no-reply@dev.example.com"` | Verified “From” address for SES. |

---

## 🔑 Worker Configuration

| Variable | Type | Example | Description |
|-----------|------|----------|--------------|
| `worker_jwt_secret` | `string` | `"randomstring"` | Secret key used by Cloudflare Worker to validate JWT tokens. |

---

## ⚡ Redis (Optional)

| Variable | Type | Example | Description |
|-----------|------|----------|--------------|
| `enable_redis` | `bool` | `false` | Enable or disable Redis creation. |
| `redis_node_type` | `string` | `"cache.t4g.micro"` | Redis instance type. |
| `redis_engine_version` | `string` | `"7.0"` | Redis engine version. |

---

## 👩‍💻 Local Development IAM (Optional)

| Variable | Type | Example | Description |
|-----------|------|----------|--------------|
| `create_local_dev_user` | `bool` | `false` | Whether to create a local developer IAM user. |
| `local_dev_user_name` | `string` | `"arcadesbox-local-dev"` | Username for the local IAM developer user. |

---

## 🧾 Notes

- All variables defined here can be overridden via `terraform.tfvars` or CLI flags (`-var`).
- Sensitive values like `r2_secret_access_key` and `worker_jwt_secret` should **never** be committed.
- If you need environment-specific overrides, maintain separate files (e.g., `terraform.dev.tfvars`, `terraform.prod.tfvars`).

---
