resource "aws_s3_bucket" "games_bucket" {
  provider = aws.r2
  bucket   = "${var.app_name_prefix}-games-cdn-${var.environment}-${var.infra_suffix}"
}


resource "aws_s3_bucket_cors_configuration" "games_bucket_cors" {
  provider = aws.r2
  bucket   = aws_s3_bucket.games_bucket.id
  cors_rule {
    allowed_headers = ["*"]
    expose_headers  = ["ETag", "Location"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_origins = ["https://${var.frontend_domain_name}"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket" "r2_backup_bucket" {
  provider = aws.r2
  # The bucket name will be something like: arcadesbox-r2-backup-dev-v1
  bucket = "${var.app_name_prefix}-r2-backup-${var.environment}-${var.infra_suffix}"
}

# Add an output to easily retrieve the R2 backup bucket name
output "r2_backup_bucket_name" {
  description = "The name of the R2 bucket for backups."
  value       = aws_s3_bucket.r2_backup_bucket.id
}
