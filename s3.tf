# s3.tf - For the AWS S3 Backup Bucket and the logs bucket

resource "aws_s3_bucket" "aws_backup_bucket" {
  bucket = "${var.app_name_prefix}-aws-backup-${var.environment}-${var.infra_suffix}"

  tags = {
    Purpose = "Backup of primary R2 game assets"
  }
}

# Enable versioning to keep a history of objects
resource "aws_s3_bucket_versioning" "aws_backup_bucket_versioning" {
  bucket = aws_s3_bucket.aws_backup_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Enforce server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "aws_backup_bucket_sse" {
  bucket = aws_s3_bucket.aws_backup_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access to ensure the bucket remains private
resource "aws_s3_bucket_public_access_block" "aws_backup_bucket_pab" {
  bucket                  = aws_s3_bucket.aws_backup_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "aws_backup_bucket_lifecycle" {
  bucket = aws_s3_bucket.aws_backup_bucket.id

  rule {
    id     = "GlacierIR-Transition-and-Expiration"
    status = "Enabled"

    filter {
      prefix = "" # Apply to all objects
    }

    # Rule for current object versions
    transition {
      days          = var.s3_backup_gir_transition_days
      storage_class = "GLACIER_IR"
    }

    # Since versioning is enabled, we should also transition old versions
    # to save costs.
    noncurrent_version_transition {
      noncurrent_days = var.s3_backup_gir_transition_days
      storage_class   = "GLACIER_IR"
    }

    # It's a best practice to eventually expire old, non-current versions
    # to prevent the bucket from growing indefinitely.
    noncurrent_version_expiration {
      noncurrent_days = var.s3_backup_expire_old_versions_days
    }
  }
}

# Add an output to easily retrieve the bucket name
output "aws_backup_bucket_name" {
  description = "The name of the S3 bucket for backups."
  value       = aws_s3_bucket.aws_backup_bucket.id
}

# =================================================================
# S3 Replication Configuration
# =================================================================

# 1. Create an IAM Role that the S3 service can assume to perform replication.
resource "aws_iam_role" "s3_replication_role" {
  name = "${var.app_name_prefix}-s3-replication-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "s3.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# 2. Define the permissions for the replication role.
resource "aws_iam_policy" "s3_replication_policy" {
  name = "${var.app_name_prefix}-s3-replication-policy-${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket",
          "s3:GetReplicationConfiguration",
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
          "s3:GetObjectRetention",
          "s3:GetObjectLegalHold"
        ],
        Resource = [
          aws_s3_bucket.aws_backup_bucket.arn,
          "${aws_s3_bucket.aws_backup_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ],
        Resource = "${aws_s3_bucket.archive_bucket.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_replication_attachment" {
  role       = aws_iam_role.s3_replication_role.name
  policy_arn = aws_iam_policy.s3_replication_policy.arn
}

# 3. Attach the replication rule to the source ("Mirror") bucket.
resource "aws_s3_bucket_replication_configuration" "mirror_to_archive" {
  depends_on = [aws_iam_role_policy_attachment.s3_replication_attachment]

  role   = aws_iam_role.s3_replication_role.arn
  bucket = aws_s3_bucket.aws_backup_bucket.id # The source bucket

  rule {
    id     = "MirrorToArchiveRule"
    status = "Enabled"

    delete_marker_replication {
      status = "Disabled"
    }

    # We want to replicate everything.
    filter {}

    destination {
      bucket        = aws_s3_bucket.archive_bucket.arn
      storage_class = "STANDARD" # It will land here, then lifecycle to Deep Archive.
    }
  }
}

# =================================================================
# ALB Access Logs Bucket
# =================================================================

resource "aws_s3_bucket" "alb_logs" {
  bucket        = "${var.app_name_prefix}-alb-logs-${var.environment}-${var.infra_suffix}"
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs_sse" {
  bucket = aws_s3_bucket.alb_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs_lifecycle" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

data "aws_elb_service_account" "main" {}

resource "aws_s3_bucket_policy" "alb_logs_policy" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = data.aws_elb_service_account.main.arn
        },
        Action   = "s3:PutObject",
        Resource = "${aws_s3_bucket.alb_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Effect = "Allow",
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        },
        Action   = "s3:PutObject",
        Resource = "${aws_s3_bucket.alb_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect = "Allow",
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        },
        Action   = "s3:GetBucketAcl",
        Resource = aws_s3_bucket.alb_logs.arn
      }
    ]
  })
}
