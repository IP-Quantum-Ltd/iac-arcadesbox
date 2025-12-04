resource "aws_dynamodb_table" "job_lock_table" {
  name         = "${var.app_name_prefix}-job-locks-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  # Enable Time To Live (TTL) to automatically clean up stale locks after they expire.
  # This is a critical safety feature.
  ttl {
    attribute_name = "ExpiresAt"
    enabled        = true
  }

  tags = {
    Purpose = "Distributed lock management for scheduled jobs"
  }
}
