terraform {
  required_version = ">= 1.12.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}

# --- Default AWS Provider ---
# This will be used for all AWS resources like VPC, ECS, etc.
# It gets its region from a variable.
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.app_name_prefix
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# --- Alias Provider for us-east-1 ---
# This is used for resources that must be in us-east-1, like ACM certs for an ALB.
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

# --- Alias Provider for Cloudflare R2 ---
# This is configured with the S3-compatible API endpoint for R2.
# It gets its credentials from variables.
provider "aws" {
  alias = "r2"

  access_key = var.r2_access_key_id
  secret_key = var.r2_secret_access_key
  region     = "auto"

  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = "https://${var.r2_account_id}.r2.cloudflarestorage.com"
  }
}

# --- Alias Provider for SES ---
# This is used for SES if it's in a different region.
provider "aws" {
  alias  = "ses_region_provider"
  region = var.ses_region
}

# --- Cloudflare Provider ---
# Used for native Cloudflare resources: Workers, KV, Queues, DNS.
# Auth via API token (set CLOUDFLARE_API_TOKEN env var or pass via variable).
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
