# s3_archive.tf - For the immutable, long-term archive bucket.

resource "aws_s3_bucket" "archive_bucket" {
  bucket = "${var.app_name_prefix}-archive-${var.environment}-${var.infra_suffix}"

  # Enable Object Lock for WORM (Write-Once-Read-Many) compliance.
  object_lock_enabled = true

  tags = {
    Purpose = "Immutable long-term archive of game assets"
  }
}

resource "aws_s3_bucket_versioning" "archive_bucket_versioning" {
  bucket = aws_s3_bucket.archive_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}
# Block all public access to ensure the bucket remains private.
resource "aws_s3_bucket_public_access_block" "archive_bucket_pab" {
  bucket                  = aws_s3_bucket.archive_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Define the default retention policy for objects in this bucket.
resource "aws_s3_bucket_object_lock_configuration" "archive_bucket_lock" {
  bucket = aws_s3_bucket.archive_bucket.id

  rule {
    default_retention {
      mode = "COMPLIANCE" # The strictest mode. Cannot be overridden even by root.
      days = 90           # Objects cannot be deleted for 90 days.
    }
  }
}

# Define a more aggressive lifecycle policy for the archive.
# We want to move data to the cheapest possible storage quickly.
resource "aws_s3_bucket_lifecycle_configuration" "archive_bucket_lifecycle" {
  bucket = aws_s3_bucket.archive_bucket.id

  rule {
    id     = "Archive-Transition-and-Expiration"
    status = "Enabled"

    filter {
      prefix = "" # Apply to all objects
    }

    # Transition current versions to DEEP_ARCHIVE for maximum cost savings.
    transition {
      days          = 30
      storage_class = "DEEP_ARCHIVE" # The cheapest storage in AWS.
    }

    # Also transition old versions.
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "DEEP_ARCHIVE"
    }

    # We can still expire very old non-current versions after a long time.
    noncurrent_version_expiration {
      noncurrent_days = 730 # e.g., expire old versions after 2 years
    }
  }
}
